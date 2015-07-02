require "sinatra"
require "./config/application"
require "erb"
require "active_support/core_ext/string"

class YoutubeError < StandardError; end
class FacebookError < StandardError; end
class InstagramError < StandardError; end

def httparty_error(r)
  "#{r.request.path.to_s}: #{r.code} #{r.message}: #{r.body}. #{r.headers.to_h.to_json}"
end


get "/" do
  erb :index
end

get "/go" do
  return "Insufficient parameters" if params[:q].empty?
  if /^https?:\/\/(www\.)?youtu(\.?be|be\.com)/ =~ params[:q]
    redirect "/youtube?q=#{params[:q]}"
  elsif /^https?:\/\/(www\.)?facebook\.com/ =~ params[:q]
    redirect "/facebook?q=#{params[:q]}"
  elsif /^https?:\/\/(www\.)?instagram\.com/ =~ params[:q]
    redirect "/instagram?q=#{params[:q]}"
  else
    "Unknown service"
  end
end

get "/youtube" do
  return "Insufficient parameters" if params[:q].empty?

  if /youtube\.com\/channel\/(?<channel_id>UC[^\/\?#]+)/ =~ params[:q]
    # https://www.youtube.com/channel/UC4a-Gbdw7vOaccHmFo40b9g/videos
  elsif /youtube\.com\/user\/(?<user>[^\/\?#]+)/ =~ params[:q]
    # https://www.youtube.com/user/khanacademy/videos
  elsif /youtube\.com\/c\/(?<user>[^\/\?#]+)/ =~ params[:q]
    # https://www.youtube.com/c/khanacademy/videos
  elsif /youtube\.com\/.*[\?&]v=(?<video_id>[^&#]+)/ =~ params[:q]
    # https://www.youtube.com/watch?v=vVXbgbMp0oY&t=5s
  elsif /youtube\.com\/(?<user>[^\/\?#]+)/ =~ params[:q]
    # https://www.youtube.com/khanacademy
  elsif /youtu\.be\/(?<video_id>[^\?#]+)/ =~ params[:q]
    # https://youtu.be/vVXbgbMp0oY?t=1s
  elsif /(?<channel_id>UC[^\/\?#]+)/ =~ params[:q]
    # it's a channel id
  else
    # it's probably a channel name
    user = params[:q]
  end

  if user
    response = HTTParty.get("https://www.googleapis.com/youtube/v3/channels?part=id&forUsername=#{user}&key=#{ENV["GOOGLE_API_KEY"]}")
    if !response.success?
      raise YoutubeError, response
    end
    if response.parsed_response["items"].length > 0
      channel_id = response.parsed_response["items"][0]["id"]
    end
  end

  if video_id
    response = HTTParty.get("https://www.googleapis.com/youtube/v3/videos?part=snippet&id=#{video_id}&key=#{ENV["GOOGLE_API_KEY"]}")
    if !response.success?
      raise YoutubeError, response
    end
    if response.parsed_response["items"].length > 0
      channel_id = response.parsed_response["items"][0]["snippet"]["channelId"]
    end
  end

  if channel_id
    redirect "https://www.youtube.com/feeds/videos.xml?channel_id=#{channel_id}"
  else
    "Could not find the channel. Sorry."
  end
end

get "/facebook" do
  return "Insufficient parameters" if params[:q].empty?

  if /facebook\.com\/(?<name>[^\/\?#]+)/ =~ params[:q]
    # https://www.facebook.com/celldweller/info?tab=overview
  else
    name = params[:q]
  end

  response = HTTParty.get("https://graph.facebook.com/v2.3/#{name}?access_token=#{ENV["FACEBOOK_APP_ID"]}|#{ENV["FACEBOOK_APP_SECRET"]}")
  return "Can't find a page with that name. Sorry." if response.code == 404
  raise FacebookError, response if !response.success?

  data = response.parsed_response
  redirect "/facebook/#{data["id"]}/#{data["username"]}"
end

get %r{/facebook/(?<id>\d+)(/(?<username>.+))?} do |id, username|
  @id = id

  response = HTTParty.get("https://graph.facebook.com/v2.3/#{id}/posts?access_token=#{ENV["FACEBOOK_APP_ID"]}|#{ENV["FACEBOOK_APP_SECRET"]}")
  raise FacebookError, response if !response.success?

  @data = response.parsed_response["data"]
  @user = @data[0]["from"]["name"] rescue username

  headers "Content-Type" => "application/atom+xml;charset=utf-8"
  erb :facebook_feed
end

get "/instagram/auth" do
  return "Already authed" if ENV["INSTAGRAM_ACCESS_TOKEN"]

  if params[:code]
    response = HTTParty.post("https://api.instagram.com/oauth/access_token", body: {
      client_id: ENV["INSTAGRAM_CLIENT_ID"],
      client_secret: ENV["INSTAGRAM_CLIENT_SECRET"],
      grant_type: "authorization_code",
      redirect_uri: request.base_url+request.path_info,
      code: params[:code]
    })
    raise InstagramError, httparty_error(response) if !response.success?
    headers "Content-Type" => "text/plain"
    "heroku config:set INSTAGRAM_ACCESS_TOKEN=#{response.parsed_response["access_token"]}"
  else
    redirect "https://api.instagram.com/oauth/authorize/?client_id=#{ENV["INSTAGRAM_CLIENT_ID"]}&redirect_uri=#{request.url}&response_type=code"
  end
end

get "/instagram" do
  return "Insufficient parameters" if params[:q].empty?

  if /instagram\.com\/p\/(?<post_id>[^\/\?#]+)/ =~ params[:q]
    # https://instagram.com/p/4KaPsKSjni/
    response = HTTParty.get("https://api.instagram.com/v1/media/shortcode/#{post_id}?access_token=#{ENV["INSTAGRAM_ACCESS_TOKEN"]}")
    return response.parsed_response["meta"]["error_message"] if !response.success?
    user = response.parsed_response["data"]["user"]
  elsif /instagram\.com\/(?<name>[^\/\?#]+)/ =~ params[:q]
    # https://instagram.com/infectedmushroom/
  else
    name = params[:q]
  end

  if name
    response = HTTParty.get("https://api.instagram.com/v1/users/search?q=#{name}&access_token=#{ENV["INSTAGRAM_ACCESS_TOKEN"]}")
    raise InstagramError, response if !response.success?
    user = response.parsed_response["data"].find { |user| user["username"] == name }
  end

  if user
    redirect "/instagram/#{user["id"]}/#{user["username"]}"
  else
    "Can't find a user with that name. Sorry."
  end
end

get %r{/instagram/(?<user_id>\d+)(/(?<username>.+))?} do |user_id, username|
  @user_id = user_id

  response = HTTParty.get("https://api.instagram.com/v1/users/#{user_id}/media/recent?access_token=#{ENV["INSTAGRAM_ACCESS_TOKEN"]}")
  if response.code == 400
    # user no longer exists or is private, show the error in the feed
    @meta = response.parsed_response["meta"]
    headers "Content-Type" => "application/atom+xml;charset=utf-8"
    return erb :instagram_error
  end
  raise InstagramError, response if !response.success?

  @data = response.parsed_response["data"]
  @user = @data[0]["user"]["username"] rescue username

  headers "Content-Type" => "application/atom+xml;charset=utf-8"
  erb :instagram_feed
end

get "/favicon.ico" do
  redirect "/img/icon32.png"
end

get %r{^/apple-touch-icon} do
  redirect "/img/icon128.png"
end

if ENV["GOOGLE_VERIFICATION_TOKEN"]
  /(google)?(?<google_token>[0-9a-f]+)(\.html)?/ =~ ENV["GOOGLE_VERIFICATION_TOKEN"]
  get "/google#{google_token}.html" do
    "google-site-verification: google#{google_token}.html"
  end
end

if ENV["LOADERIO_VERIFICATION_TOKEN"]
  /(loaderio-)?(?<loaderio_token>[0-9a-f]+)/ =~ ENV["LOADERIO_VERIFICATION_TOKEN"]
  get Regexp.new("^/loaderio-#{loaderio_token}") do
    headers "Content-Type" => "text/plain"
    "loaderio-#{loaderio_token}"
  end
end


error do
  status 500
  "Sorry, a nasty error occurred: #{env["sinatra.error"].message}"
end

error YoutubeError do
  status 503
  "There was a problem talking to YouTube."
end

error FacebookError do
  status 503
  "There was a problem talking to Facebook."
end

error InstagramError do
  status 503
  "There was a problem talking to Instagram."
end