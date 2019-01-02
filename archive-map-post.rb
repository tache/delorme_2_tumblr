#!/usr/bin/env ruby

require 'active_support'
require 'active_support/core_ext'
require 'active_support/time_with_zone'
require 'awesome_print'
require 'aws-sdk' 
require 'curb'
require 'forecast_io'
require 'geocoder'
require 'googlecharts'
require 'gpx_utils'
require 'gruff'
require 'haversine'
require 'json/ext'
require 'nokogiri'
require 'open-uri'
require 'polylines'
require 'time_difference'
require 'tumblr_client'
require 'twilio-ruby'
require 'twitter'
require 'wannabe_bool'
require 'yaml'

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
  map_zoom = 12
elsif Time.now.hour == 18
  map_zoom = 11
elsif ([21,22,23].include? Time.now.hour) or true
  map_zoom = 10
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
time_on_trail = Time.zone.now.strftime("%I:%M %p %Z")
date_on_trail = Time.zone.now.strftime("%Y-%m-%d")

# ---------------------------------------

trail_timezone = ActiveSupport::TimeZone[@TRAIL_TIMEZONE]
start_date = trail_timezone.now.beginning_of_day.utc.iso8601
puts "KML Query Start Time: #{start_date}" if verbose

start_date = "2016-05-14T00:01Z"
end_date = "2016-05-15T08:59Z"
file_date = Date.parse(start_date).end_of_day.strftime("%Y-%m-%d-%H%M")

puts "KML Query Start Time: #{start_date}" if verbose
puts "KML Query End Time: #{end_date}" if verbose
puts "File Timestamp: #{file_date}" if verbose

# ---------------------------------------

# Create a unique image name

mapImageFilename = "google_map_image_#{file_date}.png"
elevationImageFilename = "google_elevation_detail_image_#{file_date}.png"

# ---------------------------------------

# Get the KML from MapShare

c = Curl::Easy.new("https://share.delorme.com/feed/share/#{@DELORME_INREACH_MAPSHARE}?d1=#{start_date}&d2=#{end_date}")
ap c.url
c.http_auth_types = :basic
c.username = @DELORME_INREACH_MAPSHARE_ACCOUNT
c.password = @DELORME_INREACH_MAPSHARE_PASSWORD
c.perform
kml = c.body_str
# kml = File.read("./daily_kml_20160418-2101.kml")
kml_doc = Nokogiri::XML(kml)
puts "Errors: #{kml_doc.errors}" unless kml_doc.errors.empty?
if ([21,22,23].include? Time.now.hour) or true
  File.write("daily_kml_#{file_date}.kml", kml)
end

# ap kml_doc

# ---------------------------------------

# Pluck out the Point data from the KML

kml_hash = Hash.from_xml(kml_doc.to_s)

if kml_hash["kml"]["Document"]["Folder"].present?
  kml_points = kml_hash["kml"]["Document"]["Folder"]["Placemark"].reject{|ind| ind["TimeStamp"] == nil}.collect{
    |ind| { 
      "point" => {
        "latitude" => ind["ExtendedData"]["Data"][8]["value"].to_f, 
        "longitude" => ind["ExtendedData"]["Data"][9]["value"].to_f, 
        "timestamp" => ind["TimeStamp"]["when"].to_datetime, 
        "elevation" => (ind["ExtendedData"]["Data"][10]["value"].split(" ")[0].to_i * 3.2808).round(0)
      }
    }
  }

  polyline_points = kml_points.reverse.collect{|ind| [ind["point"]["latitude"], ind["point"]["longitude"]]}
  elevation_points = kml_points.collect{|ind| ind["point"]["elevation"]}
  
  location_latitude = polyline_points.first[0] unless polyline_points.empty?
  location_longitude = polyline_points.first[1] unless polyline_points.empty?

  start_location_latitude = polyline_points.last[0] unless polyline_points.empty?
  start_location_longitude = polyline_points.last[1] unless polyline_points.empty?

  start_location_timestamp = Time.parse (kml_points.first["point"]["timestamp"]).to_s unless kml_points.empty?
  end_location_timestamp = kml_points.last["point"]["timestamp"] unless kml_points.empty?
  trek_duration = TimeDifference.between(start_location_timestamp, end_location_timestamp).in_hours
  
  last_point_hash = {"latitude" => location_latitude, "longitude" => location_longitude}
  start_point_hash = {"latitude" => start_location_latitude, "longitude" => start_location_longitude}

  puts start_point_hash.to_json if verbose
  puts last_point_hash.to_json if verbose

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

g = GpxUtils::TrackImporter.new
('A'..'G').each do |ll|
  g.add_file("./gpx/tracks/CA_Sec_#{ll}_tracks.gpx")
  # puts "inject count: #{g.coords.count}"
end

# puts "---------------------------------------"

# find the closet point to the start
closest_start_poi = 0
closest_start_poi_distance = 123000
g.coords.each_with_index do |coord, index|
  coord_distance = Haversine.distance(start_location_latitude, start_location_longitude, coord[:lat], coord[:lon]).to_miles
  # puts "#{index} - #{closest_start_poi} - #{closest_start_poi_distance} - #{coord_distance} - #{coord[:lat]} - #{coord[:lon]}" if verbose
  if coord_distance < closest_start_poi_distance
    closest_start_poi_distance = coord_distance
    closest_start_poi = index
  end
end
# puts closest_start_poi_distance
puts "closest_start_poi : #{closest_start_poi}" if verbose
ap g.coords[closest_start_poi] if verbose

# puts "---------------------------------------"

# find the closet point to the end
closest_end_poi = 0
closest_end_poi_distance = 123000
g.coords.each_with_index do |coord, index|
  coord_end_distance = Haversine.distance(location_latitude, location_longitude, coord[:lat], coord[:lon]).to_miles
  # puts "#{index} - #{closest_end_poi} - #{closest_end_poi_distance} - #{coord_end_distance} - #{coord[:lat]} - #{coord[:lon]}" if verbose
  if coord_end_distance < closest_end_poi_distance
    closest_end_poi_distance = coord_end_distance
    closest_end_poi = index
  end
end

# puts closest_end_poi_distance
puts "closest_end_poi : #{closest_end_poi}" if verbose
ap g.coords[closest_end_poi] if verbose

# puts "---------------------------------------"

gpx_polyline_points_1 = g.coords[closest_end_poi - (closest_end_poi - closest_start_poi), 1000].reverse.collect{|ind| [ind[:lat], ind[:lon]]}
gpx_polyline_points =  gpx_polyline_points_1.each_slice(6).map(&:last)

track_distance = 0
previous_coord = g.coords[closest_start_poi]
g.coords[closest_start_poi + 1, (closest_end_poi - closest_start_poi)].each_with_index do |coord, index|
  p2p = Haversine.distance(previous_coord[:lat], previous_coord[:lon], coord[:lat], coord[:lon]).to_miles
  track_distance = track_distance + p2p
  previous_coord = coord
  # puts "#{closest_start_poi + index}, #{coord[:lat]}, #{coord[:lon]}, #{p2p.round(2)}"
end
puts "Distance Traveled: #{track_distance.round(2)} miles" if verbose

# puts "---------------------------------------"

distance_covered = 0
previous_coord = g.coords[0]
g.coords[0..closest_end_poi].each_with_index do |coord, index|
  p2p = Haversine.distance(previous_coord[:lat], previous_coord[:lon], coord[:lat], coord[:lon]).to_miles
  # puts "#{index} - #{distance_covered} - #{p2p}" if verbose
  distance_covered = distance_covered + p2p
  previous_coord = coord
end
fudge_factor = 5
distance_covered = distance_covered + fudge_factor
puts "Overall Distance Traveled: #{distance_covered.round(2)} miles" if verbose

if ([21,22,23].include? Time.now.hour) or true
  g_out = GpxUtils::WaypointsExporter.new
  File.write("daily_kml_#{file_date}.gpx", g_out.to_xml)
end
 
elevation_points2 = g.coords[closest_start_poi + 1, (closest_end_poi - closest_start_poi)].collect{|coord| coord[:alt] * 3.2808}
 
# ---------------------------------------

# Create a Google Static Map Image

polyline_data = Polylines::Encoder.encode_points(polyline_points)
gpx_polyline_data = Polylines::Encoder.encode_points(gpx_polyline_points)

# gm_center = new google.maps.LatLng(54, 12)

google_maps_query_string = "http://maps.google.com/maps/api/staticmap?key=#{@GOOGLE_MAPS_API_KEY}\
&scale=2\
&size=667x375\
&maptype=terrain\
&format=png\
&visual_refresh=true\
&markers=color:red%7Clabel:TSG%7C#{location_latitude}%2C#{location_longitude}\
&markers=size:mid%7Ccolor:blue%7Clabel:S%7C#{start_location_latitude}%2C#{start_location_longitude}\
&path=weight:2%7Ccolor:red%7Cenc:#{gpx_polyline_data}\
&path=weight:5%7Ccolor:green%7Cenc:#{polyline_data}"

open(mapImageFilename, 'wb') do |file|
  file << open("#{google_maps_query_string}").read
end

location_query_result = Geocoder.search("#{location_latitude},#{location_longitude}").first

# ---------------------------------------

# Get the number of days passed on the trail

start_time = Time.new(2016,4,8)
end_time = start_date
time_days = TimeDifference.between(start_time, end_time).in_days.ceil + 1

# ---------------------------------------
# xx = []
# xx << elevation_points
# xx << elevation_points2

if ([21,22,23].include? Time.now.hour) or true
  g = Gruff::Line.new('900x400')
  g.title = "PCT 2016 - Daily Elevation Trekked"
  g.font = "#{@MAGICK_FONT_PATH}/Font/Raleway/Raleway-SemiBold.ttf"
  g.title_font_size = 22
  g.legend_font_size = 14
  g.marker_font_size = 14
  g.x_axis_label = "Track Elevation Points"
  g.y_axis_label = "MSL (feet)"
  g.theme = { :colors => %w(#238829 #C7351F), :marker_color => '#aaaaaa', :font_color => 'black', :background_colors => '#dddddd'}
  g.line_width = 1.5
  g.dot_radius = 1
  g.marker_count = 5
  g.top_margin = 20 
  g.bottom_margin = 20 
  g.left_margin = 10 
  g.right_margin = 15 
  g.data "Day #{time_days} - #{Date.parse(start_date).end_of_day.strftime("%Y-%m-%d")}", elevation_points
  # g.data "GPX #{time_days} - #{time_on_trail}", elevation_points2
  g.write("./#{elevationImageFilename}")
end

# ---------------------------------------

# Get the current and forcasted weather conditions

ForecastIO.api_key = @FORECAST_IO_API_KEY
forecast = ForecastIO.forecast(location_latitude,location_longitude)
forecast_currently = "#{forecast.currently.summary}, #{forecast.currently.temperature.round} degrees, and winds of #{forecast.currently.windSpeed.round} mph"
forecast_hourly = forecast.hourly.summary

# ---------------------------------------

# Post the Tumblr blog entry
#  at #{(track_distance / trek_duration).round(1)} mph 

caption_text = "Latest location update!\nLocation Coordinates: [#{location_latitude},#{location_longitude}]\nDays into the PCT: #{time_days} days\nTime posted: #{time_on_trail}"
if !location_query_result.data.nil?
  formatted_address = location_query_result.data["formatted_address"]
  caption_text = "<h2>Archive #{Date.parse(start_date).end_of_day.strftime("%Y-%m-%d")} update!</h2>"
  caption_text << "<p><b>Location</b></p>"
  caption_text << "Approximate location: #{formatted_address}<br>"
  caption_text << "Location coordinates: [#{location_latitude.round(3)}, #{location_longitude.round(3)}]<br>"
  caption_text << "Current distance traveled today: #{track_distance.round(1)} miles<br>"
  caption_text << "Total overall distance traveled: #{distance_covered.round(1)} of 2,650 miles (#{((distance_covered/2650.to_f)*100).round(1)}%)<br>"
  caption_text << "Days into the PCT: #{time_days} days<br>"
  caption_text << "Time on the trail: #{start_date} - N/A<br>"
  caption_text << "<br>"
  caption_text << "<br>"
  caption_text << "<p><b>Notes</b></p>"
  caption_text << "<b>This is an archive post due to a technical error</b><br>"
  caption_text << "Red marker is current postion, blue marker is the day's start position, green line is what was hiked today, and red line is the PCT.<br><br>"
  caption_text << "#{@TUMBLR_SOCIAL_HASHTAGS} <br>"
end

tumblr_client = Tumblr::Client.new({
  # Authenticate via OAuth
  :consumer_key => @TUMBLR_CONSUMER_KEY,
  :consumer_secret => @TUMBLR_CONSUMER_SECRET,
  :oauth_token => @TUMBLR_OAUTH_TOKEN,
  :oauth_token_secret => @TUMBLR_OAUTH_TOKEN_SECRET
})

if post_blog_message
  if ([21,22,23].include? Time.now.hour) and true
    response = tumblr_client.photo(@TUMBLR_ACCOUNT, {:caption => caption_text, :data => ["./#{mapImageFilename}", "./#{elevationImageFilename}"]})
  else
    response = tumblr_client.photo(@TUMBLR_ACCOUNT, {:caption => caption_text, :data => ["./#{mapImageFilename}"]})
  end
  ap response if verbose
end

# ---------------------------------------

abort

# Upload the file to S3 - used in the MMS message

s3 = Aws::S3::Resource.new(
  credentials: Aws::Credentials.new(@AWS_S3_ACCESS_KEY, @AWS_S3_SECRET_KEY),
  region: 'us-east-1'
)
 
if post_blog_message
  obj = s3.bucket(@AWS_S3_BUCKET).object("#{@AWS_S3_FOLDER}/#{mapImageFilename}")
  obj.upload_file("./#{mapImageFilename}", acl: 'public-read', :content_type => "image/png")
  s3_image_url = obj.public_url
  puts "Created an map image object in S3 at: #{s3_image_url}" if verbose
end 

if post_blog_message and ([21,22,23].include? Time.now.hour)
  elevation_obj = s3.bucket(@AWS_S3_BUCKET).object("#{@AWS_S3_FOLDER}/#{elevationImageFilename}")
  elevation_obj.upload_file("./#{elevationImageFilename}", acl: 'public-read', :content_type => "image/png")
  s3_elevation_image_url = elevation_obj.public_url
  puts "Created an elevation object in S3 at: #{s3_image_url}" if verbose
end 

