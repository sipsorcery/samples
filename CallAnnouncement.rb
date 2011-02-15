# Copyright 2011 Mike Telis
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
# 15 Feb 2011	Aaron Clauson	Changes to configuration section to remove user specific information.

# Call announcement

require 'java'

SS_User     = 'your_sipsorcery_userame'          # Sipsorcery login name
TransferURI = 'your_sip_account@sipsorcery.com'  # Destination URI
AnsDeadline = 20                                 # Answer incoming call in 20 sec (to prevent it from going to VM)
AnsTimeout  = 40                            	 # Time-out waiting for user's input (to accept or not to accept)
MyName      = 'your_name'                        # Destination's name ("Looking for Mike...")
MOH         = 'http://hosting.tropo.com/40053/www/audio/Sinatra.mp3' # Music-On-Hold file

# ***************** U T I L S *****************

Start = "<?xml version='1.0'?><speak>"
End   = "</speak>"

=begin
phone_to_vxml produces VXML from *formatted* phone number. It breaks the number into chunks delimited with
spaces or dashes and then joins chunks together separating them with pauses (breaks). Options:
:pre  => String - this goes before the number
:post => String - this goes after the number
:pause => 'weak' or 'medium' or 'strong' - duration of pause between the chunks

Example:

say phone_to_vxml '+1 212 555-1212', {
                  :pre  => 'You got a call from',
                  :post => 'Press 1 to accept, 2 to reject'
                  }
=end

def phone_to_vxml num, options
  opt = { :pause => 'weak' }
  opt.update(options)

  pause = "<break strength='#{opt[:pause]}'/>"

  chunks = num.split(/\s|\-/).map do |chunk|
    chunk.gsub(/./) { |c| c =~ /\d/ ? c + ' ' : '' }.chop
  end

  Start + opt[:pre].to_s + pause + chunks.join(pause) + pause + opt[:post].to_s + End
end

=begin
formatNum formats phone number (must be in ENUM format). If 2nd parameter is true, the number will only
be formatted if it follows the rules for this particular country code.

formatNum '123456'              => +1 23456
formatNum '123456', true        => 123456
=end

def formatNum(num,exact=false)
  case num
    when /^([17])(\d{3})(\d{3})(\d{4})$/,       # USA, Russia
         /^(61)(\d)(\d{4})(\d{4})/,             # Australia
         /^(380|375|41|48|998)(\d{2})(\d{3})(\d{4})$/, # Ukraine, Belarus, Swiss, Poland, Uzbekistan
         /^(972)(\d{1,2})(\d{3})(\d{4})$/,      # Israel
         /^(36)(1|\d\d)(\d{3})(\d{3,4})$/,      # Hungary
         /^(34)(9[1-9]|[5-9]\d\d)(\d{3})(\d{3,4})$/, # Spain
         /^(86)(10|2\d|\d{3})(\d{3,4})(\d{4})$/ # China: Beijing, 2x, others 3-dig area code
      "+#$1 (#$2) #$3-#$4"

    when /^(33)(\d)(\d{2})(\d{2})(\d{2})(\d{2})$/ # France
      "+#$1 (#$2) #$3 #$4 #$5 #$6"

    when /^(44)(11\d|1\d1|2\d|[389]\d\d)(\d{3,4})(\d{4})$/ # UK 2- and 3-digit area codes
      "+#$1 (#$2) #$3 #$4"                      # 11x, 1x1, 2x, 3xx, 8xx, 9xx

    when /^(44)(\d{4})(\d{6,7})$/               # UK 4-digit area codes
      "+#$1 (#$2) #$3"

    when /^(39)(0[26]|0\d[0159]|0\d{3}|3\d\d)(\d*)(\d{4})$/,    # Italy: Milan, Rome, 0x0, 0x1, 0x5, 0x9, 4-digit
         /^(49)(1[5-7]\d|30|40|69|89|\d\d1|\d{4})(\d*)(\d{4})$/,# Germany: (mobile|2dig|3dig|4dig) area
         /^(370)(469|528|37|45|46|57|5|\d{3})(\d*)(\d{4})$/,    # Lithuania
         /^(32)(4[789]\d|[89]0\d|[2-4]|[15-8]\d)(\d*)(\d{4})$/, # Belgium
         /^(91)(11|20|33|40|44|79|80|\d{3})(\d*)(\d{4})$/,      # India
         /^(886)(37|49|89|\d)(\d*)(\d{4})$/     # Taiwan
      sep = $3[2] ? ' ' : ''                    # separator if $3 group has 3 or more digits
      "+#$1 #$2 #$3#{sep}#$4"

    when /^(420)(\d{3})(\d{3})(\d{3})$/         # Czech Republic
      "+#$1 #$2 #$3 #$4"

    when /^(37[12])(\d{3,4})(\d{4})$/           # Latvia, Estonia
      "+#$1 #$2-#$3"

    when /^(373)([67]\d{2})(\d{2})(\d{3})$/     # Moldova mobile
      "+#$1 #$2-#$3-#$4"

    when /^(373)(22|\d{3})(\d{1,2})(\d{2})(\d{2})$/ # Moldova landline
      "+#$1 (#$2) #$3-#$4-#$5"

    when /^(1|2[07]|3[0-469]|4[^2]|5[1-8]|6[0-6]|7|8[1246]|9[0-58]|\d{3})/ # all country codes
      exact ? num : "+#$1 #$'"                  # the pattern used only if exact == false

    else num    # No match - skip formatting
  end
end

# ****************** M A I N ******************

t = Time.now
callid_1 = $currentCall.getHeader("x-sbc-call-id")
from     = $currentCall.getHeader('x-sbc-from')
callid_2 = t.strftime('99%H%M%S') + "%03d" % (t.usec / 1000)    # more or less unique caller ID

from =~ /^\s*("?)([^\1]*)\1\s*<sip\:(.*)@(.*)>/
name, user, host = $2, $3, $4
user = ('1' + user) if user =~ /^[2-9]\d\d[2-9]\d{6}$/          # prepend US numbers with '1'
user.sub!(/^(\+|00|011)/,'')                                    # Remove international prefixes, if any
log "Call from: #{from}\nName: '#{name}', User: '#{user}', Host: '#{host}'"

goFlag   = false  # go transfer incoming call
doneFlag = false  # xfer Thread's done
newCall  = false

xfer = Thread.new do  # In this thread we call @TransferURI and ask whether they want to accept the call
  begin
    event = call "sip:#{TransferURI}", {
                      :callerID => "+#{callid_2}",
                      :headers  => { "x-tropo-from" => from },
                 }
    if event.name == 'answer'
      log "#{MyName} answered"
      newCall = event.value

      question = phone_to_vxml formatNum(user, true), {
              :pre  => "Call from " + (name =~ /[^0-9()\s\+\-]/ ? name + '. Number' : ''),
              :post => "Press 1 to accept, 2 to reject"
      }

      result = newCall.ask question, {
              :repeat        => 3,
              :timeout       => 5,
              :choices       => "1,2",
              :minConfidence => 0.45,
              :onHangup      => lambda {|event| log "newCall hangup!"},
              :onBadChoice   => lambda {|event| newCall.say "Wrong choice!"}
      }

      log "Got: #{result.name}, #{result.value}"

      if result.name == "choice"
        case result.value
          when "1"    # When the user has selected "Yes"
            goFlag = true
            newCall.say "Call accepted, connecting"
          else
            newCall.say "Rejecting incoming call"
        end
      end
    end
  rescue
    log "Exception: '#$!'"
    case $!.to_s 
      when "Call dropped", "Answer timeout" # handle both in the same manner
        wait 500
        newCall.say "Too late, incoming call dropped" if newCall
        goFlag = false
    end
  ensure
    doneFlag = true
  end
end

# Main thread

status = ''
AnsTimeout.times do |i|     # Here we're monitoring incoming call to detect hangup
# wait 1000  # *********** replaced with sleep, interferes with ask in xfer thread!
  sleep 1    # check every second
  # answer incoming call if we can't wait any longer, play music-on-hold
  Thread.new { answer; wait 2000; say "Looking for #{MyName}, please hold. #{MOH}" } if i == AnsDeadline
  status = $currentCall.state
  log "State = " + status
  if status == "DISCONNECTED"
    xfer.raise "Call dropped" # Notify xfer thread
    break
  end
  break if doneFlag
end

xfer.raise "Answer timeout" unless doneFlag   # !doneFlag means AnsTimeout secs passed with no decision

xfer.join

if goFlag
  Thread.new { newCall.say(MOH) }     # start playing music-on-hold
  
  answer unless status == "ANSWERED"  # answer incoming cal if not already
  wait 1000

#  say "Your call is being connected"

  # initiate dual transfer
  svcURL = "http://www.sipsorcery.com/callmanager.svc/dualtransfer?user=#{SS_User}&callid1=#{callid_1}&callid2=#{callid_2}"
  log "URL:" + svcURL
  url= java.net.URL.new svcURL
  conn = url.openConnection
  log "javaURL created"
  stm = conn.getInputStream
  transferResult = org.apache.commons.io.IOUtils.toString(stm)

  unless transferResult.empty?
    say "Transfer failed"
    log "Dual transfer failed:\n" + transferResult
  end
end

# Clean-up
case $currentCall.state
  when "RINGING"  then reject
  when "ANSWERED"
    say "Unable to locate #{MyName}"
    hangup
end
newCall.hangup if newCall