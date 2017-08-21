# http://ustream.github.io/api-docs/broadcasting-api/channel.html

class UstreamParty < HTTP
  BASE_URL = "https://api.ustream.tv"
end

class UstreamError < PartyError; end

error UstreamError do |e|
  status 503
  "There was a problem talking to Ustream."
end
