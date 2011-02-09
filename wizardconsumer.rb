require 'mikesgem'

settings = lookup.GetSettings()
Tz = settings.GetTimezoneOffset()
Country = settings.Options.countrycode
Area = settings.Options.areacode
EnableSafeguards = settings.Options.enablesafeguards
WP_key = settings.Options.whitepageskey
sys.Log("Enable Safeguards=#{EnableSafeguards}.")
Allowed_Country = settings.GetAllowedCountries()
EnumDB = settings.GetENUMServers()
ExcludedPrefixes = settings.GetExcludedPrefixes()
Speeddial = settings.GetSpeedDials()
CNAM = settings.GetCNAMs()
MyENUM = settings.GetENUMs()
Routes = settings.Routes
Providers = {}
settings.Providers.each { |p|
  Providers[p.key] = VSP.new p.value.providerprefix, p.value.providerdialstring, p.value.providerdescription
}

require 'dialplanwizard'