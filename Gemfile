source "https://rubygems.org"

ruby ">= 2.8.0"

gem "rake", require: false
gem "irb"
gem "rack"
gem "sinatra"
gem "puma"
gem "dotenv"
gem "redis"
gem "addressable"
gem "rack-ssl-enforcer"
gem "secure_headers"
gem "clogger", git: "http://bogomips.org/clogger.git"
gem "tzinfo"
gem "nokogiri"
gem "prometheus-client", require: "prometheus/middleware/exporter"

# dilbert feed
gem "feedjira"
gem "opengraph_parser"

gem "airbrake", require: false
gem "newrelic_rpm", require: false

group :development do
  gem "sinatra-contrib", require: "sinatra/reloader"
  gem "powder"
  # gem "binding_of_caller"
  # gem "better_errors"
  gem "pry-remote"
  gem "github-release-party"
end
