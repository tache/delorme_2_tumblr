#!/usr/bin/env ruby

require 'active_support'
require 'active_support/core_ext'
require 'awesome_print'
require 'curb'
require 'forecast_io'
require 'geocoder'
require 'json/ext'
require 'nokogiri'
require 'open-uri'
require 'polylines'
require 'time_difference'
require 'tumblr_client'
require 'aws-sdk' 
require 'wannabe_bool'
require 'yaml'
require 'twilio-ruby'
require 'twitter'

# ---------------------------------------

# Get the apps defaults

unless ARGV[0] and ARGV[1] and ARGV[2] and ARGV[3]
  puts "\nYou need to the number of days and the debugging flag\n"
  puts "Usage: tumblr-map-post.rb [# DAYS] [debug yes/no] [post yes/no] [map zoom level]\n"
  exit
end

start_date = ARGV[0].to_i.days.ago.utc.iso8601
verbose = ARGV[1].to_b
post_blog_message = ARGV[2].to_b
map_zoom = ARGV[3].to_i

if Time.now.hour == 14
  map_zoom = 16
elsif Time.now.hour == 18
  map_zoom = 12
elsif Time.now.hour == 21
  map_zoom = 8
else
  map_zoom = ARGV[3].to_i
end

# ---------------------------------------

# Get all the environmental variables - the super secret ones. Modify the template

config = YAML.load_file("config.yml")
config["config"].each { |key, value| instance_variable_set("@#{key}", value) }

# ---------------------------------------

# Get the time on the trail

Time.zone = "Pacific Time (US & Canada)"
time_on_trail = Time.zone.now.strftime("%B %e, %Y at %I:%M %p %Z")

# ---------------------------------------

# Create a unique image name

mapImageFilename = "google_map_image_#{Time.now.strftime("%Y%m%d%H%M%S")}.png"

# ---------------------------------------

# Get the KML from MapShare

c = Curl::Easy.new("https://share.delorme.com/feed/share/#{@DELORME_INREACH_MAPSHARE}?d1=#{start_date}")
c.http_auth_types = :basic
c.username = @DELORME_INREACH_MAPSHARE_ACCOUNT
c.password = @DELORME_INREACH_MAPSHARE_PASSWORD
c.perform
kml = c.body_str
kml_doc = Nokogiri::XML(kml)
puts "Errors: #{kml_doc.errors}" unless kml_doc.errors.empty?

# ---------------------------------------

# Pluck out the Point data from the KML

kml_hash = Hash.from_xml(kml_doc.to_s)

if kml_hash["kml"]["Document"]["Folder"].present?
  kml_points = kml_hash["kml"]["Document"]["Folder"]["Placemark"].reject{|ind| ind["TimeStamp"] == nil}.collect{|ind| [ind["ExtendedData"]["Data"][8]["value"].to_f, ind["ExtendedData"]["Data"][9]["value"].to_f, ind["TimeStamp"]["when"].to_datetime]} if kml_hash["kml"]["Document"]["Folder"].present?

  polyline_points = kml_points.reverse.collect{|ind| [ind[0],ind[1]]}
  location_latitude = polyline_points.first[0] unless polyline_points.empty?
  location_longitude = polyline_points.first[1] unless polyline_points.empty?
  last_point_hash = {"latitude" => location_latitude, "longitude" => location_longitude}

  puts "#{time_on_trail} - Last waypoint - #{last_point_hash.to_json}" if verbose
  # puts last_point_hash.to_json if verbose
  # puts kml_points.to_json if verbose
else
  kml_points = []
  puts "#{time_on_trail} - No new waypoints found!" if verbose
  abort
end

 # this is for testing
 # polyline_points = []
 # location_latitude = 32.7120425
 # location_longitude = -117.172764
 # map_zoom = 14
 
# ---------------------------------------

# Create a Google Static Map Image

polyline_data = Polylines::Encoder.encode_points(polyline_points)

google_maps_query_string = "http://maps.google.com/maps/api/staticmap?key=#{@GOOGLE_MAPS_API_KEY}\
&zoom=#{map_zoom}\
&scale=1\
&size=667x375\
&maptype=terrain\
&format=png\
&visual_refresh=true\
&center=#{location_latitude}%2C#{location_longitude}\
&markers=#{location_latitude}%2C#{location_longitude}\
&path=weight:3%7Ccolor:orange%7Cenc:#{polyline_data}"

open(mapImageFilename, 'wb') do |file|
  file << open("#{google_maps_query_string}").read
end

location_query_result = Geocoder.search("#{location_latitude},#{location_longitude}").first

# ---------------------------------------

# Get the number of days passed on the trail

start_time = Time.new(2016,4,8)
end_time = Time.now
time_days = TimeDifference.between(start_time, end_time).in_days.floor 

# ---------------------------------------

# Get the current and forcasted weather conditions

ForecastIO.api_key = @FORECAST_IO_API_KEY
forecast = ForecastIO.forecast(location_latitude,location_longitude)
forecast_currently = "#{forecast.currently.summary}, #{forecast.currently.temperature.round} degrees, and winds of #{forecast.currently.windSpeed.round} mph"
forecast_hourly = forecast.hourly.summary

# ---------------------------------------

# Post the Tumblr blog entry

caption_text = "Latest location update for #{@TUMBLR_HIKER_NAME}!\nLocation Coordinates: [#{location_latitude},#{location_longitude}]\nDays into the PCT: #{time_days} days\nTime posted: #{time_on_trail}"
if !location_query_result.data.nil?
  formatted_address = location_query_result.data["formatted_address"]
  caption_text = "<h2>Latest location update for #{@TUMBLR_HIKER_NAME}!</h2>"
  caption_text << "<p><b>Location<b></p>"
  caption_text << "Approximate location: #{formatted_address}<br>Location Coordinates: [#{location_latitude},#{location_longitude}]<br>Days into the PCT: #{time_days} days<br>Time posted: #{time_on_trail}<br><br>"
  caption_text << "<p><b>Weather<b></p>"
  caption_text << "Current conditions: #{forecast_currently}<br>Forecast: #{forecast_hourly}<br><br>"
  if !forecast.alerts.nil?
    caption_text << "<p style=\"color:red;\"><b>Weather Alerts</b></p>"
    forecast.alerts.each do |alert|
      caption_text << alert.title + "<br>"
    end
  end
  caption_text << "#pacificcresttrail #hikers #pct2016 #PCTA #pct <br>"
end

tumblr_client = Tumblr::Client.new({
  # Authenticate via OAuth
  :consumer_key => @TUMBLR_CONSUMER_KEY,
  :consumer_secret => @TUMBLR_CONSUMER_SECRET,
  :oauth_token => @TUMBLR_OAUTH_TOKEN,
  :oauth_token_secret => @TUMBLR_OAUTH_TOKEN_SECRET
})

if post_blog_message
  response = tumblr_client.photo(@TUMBLR_ACCOUNT, {:caption => caption_text, :data => ["./#{mapImageFilename}"]})
  ap response
end

# ---------------------------------------

# Post the Twitter Tweet

twitter = Twitter::REST::Client.new do |twitter_config|
  twitter_config.consumer_key = @TWITTER_CONSUMER_KEY
  twitter_config.consumer_secret = @TWITTER_CONSUMER_SECRET
  twitter_config.access_token = @TWITTER_ACCESS_TOKEN
  twitter_config.access_token_secret = @TWITTER_ACCESS_TOKEN_SECRET
end

if post_blog_message
  twitter.update_with_media("Current Location!\nDays into #pacificcresttrail #{time_days}\nWeather: #{forecast.currently.temperature.round} °F with winds of #{forecast.currently.windSpeed.round} mph\n#hikers #pct2016 #PCTA #pct", 
    File.new("./#{mapImageFilename}"),
    lat: location_latitude, 
    long: location_longitude, 
    display_coordinates: true)
end

# ---------------------------------------

# Upload the file to S3 - used in the MMS message

s3 = Aws::S3::Resource.new(
  credentials: Aws::Credentials.new(@AWS_S3_ACCESS_KEY, @AWS_S3_SECRET_KEY),
  region: 'us-east-1'
)
 
obj = s3.bucket(@AWS_S3_BUCKET).object("#{@AWS_S3_FOLDER}/#{mapImageFilename}")
obj.upload_file("./#{mapImageFilename}", acl: 'public-read', :content_type => "image/png")
s3_image_url = obj.public_url
puts "Created an object in S3 at: #{s3_image_url}" if verbose

# ---------------------------------------

# Send the SMS message notifications.

twilio_client = Twilio::REST::Client.new @TWILIO_ACCOUNT_SID, @TWILIO_AUTH_TOKEN
 
sms_recipient_list = JSON.parse(@SMS_RECIPIENTS)

if post_blog_message
  sms_recipient_list.each do |key, value|
    response = twilio_client.account.messages.create(
      :from => @TWILIO_NUMBER,
      :to => key,
      :body => "Latest location update for #{@TUMBLR_HIKER_NAME}! See the blog entry at #{@TUMBLR_BLOG_URL}",
  	  :media_url => s3_image_url,
    )
    ap response.status if verbose
    puts "Sent message to #{value}"
  end
end
