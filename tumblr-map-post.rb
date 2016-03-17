require 'active_support'
require 'active_support/core_ext'
require 'awesome_print'
require 'curb'
require 'ffaker'
require 'forecast_io'
require 'geocoder'
require 'json/ext'
require 'nokogiri'
require 'open-uri'
require 'polylines'
require 'time_difference'
require 'tumblr_client'
require 'aws-sdk' 

start_date = "2016-3-15T11:41:26Z"

# ---------------------------------------

# setup Keys
google_maps_api_key = ENV['GOOGLE_MAPS_API_KEY']
tumblr_account = ENV['TUMBLR_ACCOUNT']
client = Tumblr::Client.new({
  # Authenticate via OAuth
  :consumer_key => ENV['TUMBLR_CONSUMER_KEY'],
  :consumer_secret => ENV['TUMBLR_CONSUMER_SECRET'],
  :oauth_token => ENV['TUMBLR_OAUTH_TOKEN'],
  :oauth_token_secret => ENV['TUMBLR_OAUTH_TOKEN_SECRET']
})

# Debugging
# ap client.info

# ---------------------------------------

c = Curl::Easy.new("https://share.delorme.com/feed/share/#{ENV['DELORME_INREACH_MAPSHARE']}?d1=#{start_date}")
c.http_auth_types = :basic
c.username = ENV['DELORME_INREACH_MAPSHARE_ACCOUNT']
c.password = ENV['DELORME_INREACH_MAPSHARE_PASSWORD']
c.perform
kml = c.body_str
kml_doc = Nokogiri::XML(kml)
puts "Errors: #{kml_doc.errors}" unless kml_doc.errors.empty?

# Debugging
# ap kml_doc

# ---------------------------------------

kml_hash = Hash.from_xml(kml_doc.to_s)

kml_points = []

kml_points = kml_hash["kml"]["Document"]["Folder"]["Placemark"].reject{|ind| ind["TimeStamp"] == nil}.collect{|ind| [ind["ExtendedData"]["Data"][8]["value"].to_f, ind["ExtendedData"]["Data"][9]["value"].to_f, ind["TimeStamp"]["when"].to_datetime]} if kml_hash["kml"]["Document"]["Folder"].present?

polyline_points = kml_points.reverse.collect{|ind| [ind[0],ind[1]]}
location_latitude = polyline_points.first[0] unless polyline_points.empty?
location_longitude = polyline_points.first[1] unless polyline_points.empty?

# Debugging
# ap kml_hash
# ap polyline_points

# ---------------------------------------

map_zoom = 11

polyline_data = Polylines::Encoder.encode_points(polyline_points)

google_maps_query_string = "http://maps.google.com/maps/api/staticmap?key=#{google_maps_api_key}\
&zoom=#{map_zoom}\
&scale=1\
&size=667x375\
&maptype=terrain\
&format=png\
&visual_refresh=true\
&center=#{location_latitude}%2C#{location_longitude}\
&markers=#{location_latitude}%2C#{location_longitude}\
&path=weight:3%7Ccolor:orange%7Cenc:#{polyline_data}"

open('google_map_image.png', 'wb') do |file|
  file << open("#{google_maps_query_string}").read
end

location_query_result = Geocoder.search("#{location_latitude},#{location_longitude}").first

# ap google_maps_query_string
# ap location_query_result
# ap location_query_result.data

# ---------------------------------------

start_time = Time.new(2016,1,1)
end_time = Time.now
time_days = TimeDifference.between(start_time, end_time).in_days.floor 

# ---------------------------------------

Time.zone = "Pacific Time (US & Canada)"
time_on_trail = Time.zone.now.strftime("%B %e, %Y at %I:%M %p %Z")

# ---------------------------------------

ForecastIO.api_key = ENV['FORECAST_IO_API_KEY']
forecast = ForecastIO.forecast(location_latitude,location_longitude)
forecast_currently = "#{forecast.currently.summary}, #{forecast.currently.temperature.round} degrees, and winds of #{forecast.currently.windSpeed.round} mph"
forecast_hourly = forecast.hourly.summary

# Debugging
# ap forecast
# puts forecast.currently
# puts forecast.currently.summary

# ---------------------------------------

tumblr_hiker_name =  ENV['TUMBLR_HIKER_NAME']
caption_text = "Latest location update for #{tumblr_hiker_name}!\nLocation Coordinates: [#{location_latitude},#{location_longitude}]\nTime on the PCT: #{time_days} days\nTime posted: #{time_on_trail}"
if !location_query_result.data.nil?
  formatted_address = location_query_result.data["formatted_address"]
  caption_text = "<h2>Latest location update for #{tumblr_hiker_name}!</h2>"
  caption_text << "<p><b>Location<b></p>"
  caption_text << "Approximate location: #{formatted_address}<br>Location Coordinates: [#{location_latitude},#{location_longitude}]<br>Time on the PCT: #{time_days} days<br>Time posted: #{time_on_trail}<br><br>"
  caption_text << "<p><b>Weather<b></p>"
  caption_text << "Current conditions: #{forecast_currently}<br>Forecast: #{forecast_hourly}<br><br>"
  if !forecast.alerts.nil?
    caption_text << "<p style=\"color:red;\"><b>Weather Alerts</b></p>"
    forecast.alerts.each do |alert|
      caption_text << alert.title + "<br>"
    end
  end
end

# Debugging
# puts caption_text

response = client.photo(tumblr_account, {:caption => caption_text, :data => ['./google_map_image.png']})

# Debugging
# ap response


