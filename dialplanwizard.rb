# Copyright 2010 Mike Telis
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.
#
# Modifications:
# 9 Feb 2011	Aaron Clauson	Crudely hacked around with to work with new dial plan wizard web configuration page.

require 'mikesgem'

Host     = 'sipsorcery.com'        # Replaces "host" on incoming calls

def selectVSP    # VoIP provider selection

  providerFound = false;
  Routes.each {|x| 
    if @num =~ /^(#{x.routepattern})/ && Providers[x.routedestination]
	  sys.Log("provider selected #{x.routedestination}.")
	  providerFound = true;
	  route_to Providers[x.routedestination], x.routedescription, nil
	end
  }

  if providerFound
    rejectCall(603, "Call failed on all attempted providers")
  else
    rejectCall(603, "No provider matched for number")
    #route_to F9default
  end
end

# ********************  i n c o m i n g   C a l l  *************************

def incomingCall
  sys.SetFromHeader(formatNum(@cname || @cid,true), nil, Host)  # Set FromName & FromHost for sys.Dial

  # Forward call to the bindings (ATA / softphone)
  # Change FromURI when forwarding to @local, or else Bria won't find contact in its phonebook!

  callswitch("#{@user}@local[fu=#{@cid}]",45) unless (30..745) === @t.hour*100 + @t.min # reject incoming calls from 0:30a to 7:45a

  @code, @reason = 480, "#{@user} is asleep" unless @code # if nothing else, must be the night hour
  @code = 486 if @trunk =~ /IPCOMM/i ## *** temporary fix for IPCOMMS ***
end

# **************************  t o   E N U M  *******************************

def to_ENUM num
  num.gsub!(/[^0-9*+]/,'') # Delete all fancy chars (only digits, '+' and '*' allowed)

  # Check if the number begins with one of international prefixes:
  #  '+' - international format
  #   00 - European style international prefix (00)
  #  011 - US style international prefix (011)
  #  0011 - Australian style international prefix (0011)

  num =~ /^(\+|0011|00|011)/ and return $' # if yes, remove prefix and return

  case num                    # Special cases
    when /^0(\d+)$/       	  # National number.
      Country + $1        	  # Prefix with country code.
    when /^[1-9]\d+$/ 		  # Local number.
      Country + Area + num    # Prefix with country and area code.
    when /^\*/                # Voxalot voicemail, echotest & other special numbers
      num                     # ... as is
    else
      rejectCall(603,"Wrong number: '#{num}', check & dial again")
  end
end

# ****** E N D   O F   C O N F I G U R A T I O N    S E C T I O N ******** #

# **************************  C A L L    S W I T C H  **********************

def callswitch(num,*args)
  @timeout = args[0]
  num.gsub!(/%([0-9A-F]{2})/) {$1.to_i(16).chr} # Convert %hh into ASCII
  @num = Speeddial.ContainsKey(num) ? Speeddial[num] : num  # If there is speed dial entry for it...

  if @num =~ /@/              # If we already have URI, just dial and return
    sys.Log("URI dialing: #@num")
    dial(@num,*args)
  else  
    # Not URI
    rexp = VSP.tab.keys.sort {|a,b| b.length <=> a.length}.map {|x| Regexp.escape(x)}.join('|')
    if @num =~ /^(#{rexp})/   # If number starts with VSP selection prefix
      @num = $'
	  @forcedRoute = VSP.tab[$1]
      @noSafeGuards = (@forcedRoute.fmt =~ /Disable\s*Safe\s*Guards/i)
    end

    @num = to_ENUM(@num)      # Convert to ENUM

    rejectCall(503,"Number's empty") if @num.empty?
    sys.Log("Number in ENUM format: #{@num}")
    if @forcedRoute && !@noSafeGuards
      route_to @forcedRoute, "Forced routing!", false # if forced with prefix, skip ENUM, safeguards & VSP selection
    else
      checkNum if EnableSafeguards && !@noSafeGuards
      selectVSP               # Pick appropriate provider for the call
    end
  end   # URI
end

# ***************************  R O U T E _ T O  ****************************

def route_to vsp, dest=nil, enum = EnumDB
  enum.to_a.each do |db|   # if enum enabled, look in all enum databases
    sys.Log("enum lookup in #{db}")
    if uri = (db.class == Hash)? db[@num] : sys.ENUMLookup("#{@num}.#{db}")
      sys.Log("ENUM entry found: '#{uri}' in #{db.class == Hash ? 'local' : db} database")
      dial(uri)
    end
  end                   # ENUM not found or failed, call via regular VSP

  return unless vsp     # No VSP - do nothing

  uri = vsp.fmt.gsub(/\s+/,'').gsub(/\$\{EXTEN(:([^:}]+)(:([^}]+))?)?\}/) {@num[$2.to_i,$4? $4.to_i : 100]}
  dest &&= " (#{dest})"; with = vsp.name; with &&= " with #{with}"
  sys.Log("Calling #{formatNum(@num)}#{dest}#{with}")

  if vsp.is_gv?
    vsp.repeat.times do |i|
      @code, @reason = 200, "OK"  # assume OK
      sys.GoogleVoiceCall *vsp.getparams(uri, i + (vsp.rand ? @t.to_i : 0))
      sys.Log("Google Voice Call failed!")
      @code, @reason = 603, 'Service Unavailable'
    end
  else
    vsp.repeat.times do
      dial(uri, @timeout || vsp.tmo || 300) # Dial, global time-out overrides account
    end
  end
end

# *******************************  D I A L  ********************************

def dial *args
  @code, @reason = nil
  sys.Dial *args    # dial URI
  status()          # We shouldn't be here! Get error code...
  sys.Log("Call failed: code #{@code}, #{@reason}")
end

# *****************************  S T A T U S  ******************************

def status
  begin
    @code, @reason = 487, 'Cancelled by Sipsorcery'
    sys.LastDialled.each do |ptr|
      if ptr
        ptr = ptr.TransactionFinalResponse
        @code = ptr.StatusCode; @reason = ptr.ReasonPhrase; break if @code == 200
#       sys.Log("#{ptr.ToString()}")
      end
    end
  rescue
  end
end

# ************************  r e j e c t C a l l  ***************************

def rejectCall code, reason
  @code = code; @reason = reason
  sys.Respond code, reason
end

# ****************************  C H E C K   N U M **************************

def checkNum
  return if @num.match(/^\D/)  # skip if number doesn't begin with a digit

  # Reject calls to not blessed countries and premium numbers
  # (unless VSP was forced using #n dial prefix)

  if(Allowed_Country != nil) then
	  rejectCall(503,"Calls to code #{formatNum(@num).split(' ')[0]} not allowed") \
		unless @num.match "^(#{Allowed_Country.join('|')})"
  end

  if(ExcludedPrefixes != nil) then
	  rejectCall(503,"Calls to '#{formatNum($&)}' not allowed") if @num.match \
		'^(' + ExcludedPrefixes.map { |x| "(:?#{x.gsub(/\s*/,'')})" }.join('|') + ')'
  end
end

# **********************  k e y s   t o   E N U M  *************************

def keys_to_ENUM (table)
  Hash[*table.keys.map! {|key| to_ENUM(key.dup)}.zip(table.values).flatten]
end

# **************************  g e t T I M E  *******************************

def getTime
  Time.now.utc + Tz * 60 # Get current UTC time and adjust to local.
end

# *******************************  M A I N  ********************************

begin
  sys.Log("** Call from #{req.Header.From} to #{req.URI.User} **")
  sys.ExtendScriptTimeout(15)   # preventing long running dialscript time-out
  @t = getTime()
  sys.Log(@t.strftime('Local time: %c'))
  if EnumDB != nil then
    EnumDB.map! {|x| x.class == Hash ? keys_to_ENUM(x) : x } # rebuild local ENUM table
  end
  
  if sys.In               # If incoming call...
    @cid = req.Header.from.FromURI.User.to_s    # Get caller ID

    # Prepend 10-digit numbers with "1" (US country code) and remove int'l prefix (if present)

    @cid = ('1' + @cid) if @cid =~ /^[2-9]\d\d[2-9]\d{6}$/
    @cid.sub!(/^(\+|00|011)/,'')   # Remove international prefixes, if any

    prs = req.URI.User.split('.')  # parse User into chunks
    @trunk = prs[-2]               # get trunk name
    @user  = prs[-1]               # called user name

    # Check CNAM first. If not found and US number, try to lookup caller's name in Whitepages

    if !(@cname = keys_to_ENUM(CNAM)[@cid]) && @cid =~ /^1([2-9]\d\d[2-9]\d{6})$/ && defined?(WP_key)
      url = "http://query.yahooapis.com/v1/public/yql?q=select%20*%20from%20xml%20where%20url%3D'http%3A%2F%2Fapi.whitepages.com%2Freverse_phone%2F1.0%2F%3Fphone%3D#{$1}%3Bapi_key%3D#{WP_key}'%20and%20itemPath%3D'wp.listings.listing'&format=json"
      if js = sys.WebGet(url,4).to_s
        @cname, dname, city, state = %w(businessname displayname city state).map {|x| js =~ /"#{x}":"([^"]+)"/; $1}
        @cname ||= dname; @cname ||= "#{city}, #{state}" if city && state
      end
    end

    sys.Log("Caller's number: '#{@cid}'"); sys.Log("Caller's name:   '#{@cname}'") if @cname
    incomingCall()        # forward incoming call

  else                    # Outbound call ...

    # check if it's URI or phone number.
    # If destination's host is in our domain, it's a phone call

    num = req.URI.User.to_s; reqHost = req.URI.Host.to_s  # Get User and Host
    host = reqHost.downcase.split(':')[0]                 # Convert to lowercase and delete optional ":port"
    num << '@' << reqHost unless sys.GetCanonicalDomain(host) != nil   # URI dialing unless host is in our domain list

    callswitch(num)

  end
  sys.Respond(@code,@reason) # Forward error code to ATA
rescue
   # Gives a lot more details at what went wrong (borrowed from Myatus' dialplan)
   sys.Log("** Error: " + $!) unless $!.to_s =~ /Thread was being aborted./
end