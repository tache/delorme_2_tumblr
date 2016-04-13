#!/usr/bin/env ruby

require 'active_support'
require 'active_support/core_ext'
require 'active_support/time_with_zone'
require 'awesome_print'
require 'curb'
require 'forecast_io'
require 'googlecharts'
require 'gpx_utils'
require 'haversine'
require 'json'
require 'json/ext'
require 'nokogiri'
require 'open-uri'
require 'polylines'
require 'rchart'
require 'time_difference'
require 'wannabe_bool'
require 'yaml'

# ---------------------------------------

unless ARGV[0] and ARGV[1]
  puts "\nYou need to the number of days and the debugging flag\n"
  puts "Usage: delorme-kml-parse.rb [# DAYS] [yes/no] [map zoom level]\n"
  exit
end

start_date = ARGV[0].to_i.days.ago.utc.iso8601
verbose = ARGV[1].to_b
map_zoom = ARGV[2].to_i

# ---------------------------------------

config = YAML.load_file("config.yml")
config["config"].each { |key, value| instance_variable_set("@#{key}", value) }

# ---------------------------------------

# Create a unique image name

mapImageFilename = "google_map_image_#{Time.now.strftime("%Y%m%d%H%M%S")}.png"
elevationImageFilename = "google_elevation_detail_image_#{Time.now.strftime("%Y%m%d-%H%M")}.png"

# ---------------------------------------

trail_timezone = ActiveSupport::TimeZone[@TRAIL_TIMEZONE]
start_date = trail_timezone.now.beginning_of_day.utc.iso8601
# start_date = ARGV[0].to_i.days.ago.utc.iso8601

# ---------------------------------------

# Get the KML from MapShare

c = Curl::Easy.new("https://share.delorme.com/feed/share/#{@DELORME_INREACH_MAPSHARE}?d1=#{start_date}")
c.http_auth_types = :basic
c.username = @DELORME_INREACH_MAPSHARE_ACCOUNT
c.password = @DELORME_INREACH_MAPSHARE_PASSWORD
c.perform
kml = c.body_str
File.write("daily_kml_#{Time.now.strftime("%Y%m%d%H%M%S")}.kml", kml)
kml_doc = Nokogiri::XML(kml)
puts "Errors: #{kml_doc.errors}" unless kml_doc.errors.empty?
# ap kml_doc

# ---------------------------------------

# Pluck out the Point data from the KML

kml_hash = Hash.from_xml(kml_doc.to_s)
ap kml_hash if verbose

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
  elevation_points = kml_points.reverse.collect{|ind| ind["point"]["elevation"]}
  
  # ap elevation_points
  # ap polyline_points
  
  location_latitude = polyline_points.first[0] unless polyline_points.empty?
  location_longitude = polyline_points.first[1] unless polyline_points.empty?
  
  start_location_latitude = polyline_points.last[0] unless polyline_points.empty?
  start_location_longitude = polyline_points.last[1] unless polyline_points.empty?

  # Create Point 
  last_point_hash = {"last_point" => {"latitude" => location_latitude, "longitude" => location_longitude}}
  start_point_hash = {"start_point" => {"latitude" => start_location_latitude, "longitude" => start_location_longitude}}

  puts start_point_hash.to_json if verbose
  puts last_point_hash.to_json if verbose

  # puts kml_points.to_json if verbose
else
  kml_points = []
  puts "No new waypoints found!" if verbose
  abort
end

# ap kml_points

# ap location_latitude
# ap location_longitude

# ---------------------------------------

g = GpxUtils::TrackImporter.new
('A'..'B').each do |ll|
  g.add_file("./gpx/CA_Sec_#{ll}_tracks.gpx")
end

closest_start_poi = 0
closest_start_poi_distance = 123000
g.coords.each_with_index do |coord, index|
  coord_distance = Haversine.distance(start_location_latitude, start_location_longitude, coord[:lat], coord[:lon]).to_miles
  if coord_distance < closest_start_poi_distance
    closest_start_poi_distance = coord_distance
    closest_start_poi = index
  end
end
# puts closest_start_poi_distance
puts "closest_start_poi : #{closest_start_poi}"
ap g.coords[closest_start_poi]

closest_end_poi = 0
closest_end_poi_distance = 123000
g.coords.each_with_index do |coord, index|
  coord_distance = Haversine.distance(location_latitude, location_longitude, coord[:lat], coord[:lon]).to_miles
  if coord_distance < closest_end_poi_distance
    closest_end_poi_distance = coord_distance
    closest_end_poi = index
  end
end

# puts closest_end_poi_distance
puts "closest_end_poi : #{closest_end_poi}"
ap g.coords[closest_end_poi]

gpx_polyline_points_1 = g.coords[closest_end_poi - (closest_end_poi - closest_start_poi), 1600].reverse.collect{|ind| [ind[:lat], ind[:lon]]}
gpx_polyline_points =  gpx_polyline_points_1.each_slice(6).map(&:last)

track_distance = 0
previous_coord = g.coords[closest_start_poi]
g.coords[closest_start_poi + 1, (closest_end_poi - closest_start_poi)].each_with_index do |coord, index|
  p2p = Haversine.distance(previous_coord[:lat], previous_coord[:lon], coord[:lat], coord[:lon]).to_miles
  track_distance = track_distance + p2p
  previous_coord = coord
  # puts "#{closest_start_poi + index}, #{coord[:lat]}, #{coord[:lon]}, #{p2p.round(2)}"
end
puts "Distance Traveled: #{track_distance.round(2)}"

g_out = GpxUtils::WaypointsExporter.new
File.write("daily_kml_#{Time.now.strftime("%Y%m%d%H%M%S")}.gpx", g_out.to_xml)

# ---------------------------------------

# Create a Google Static Map Image

gpx_polyline_data = Polylines::Encoder.encode_points(gpx_polyline_points)
polyline_data = Polylines::Encoder.encode_points(polyline_points)

google_maps_query_string = "http://maps.google.com/maps/api/staticmap?key=#{@GOOGLE_MAPS_API_KEY}\
&zoom=#{map_zoom}\
&scale=1\
&size=667x375\
&maptype=terrain\
&format=png\
&visual_refresh=true\
&center=#{location_latitude}%2C#{location_longitude}\
&markers=color:red%7Clabel:TSG%7C#{location_latitude}%2C#{location_longitude}\
&markers=size:mid%7Ccolor:blue%7Clabel:S%7C#{start_location_latitude}%2C#{start_location_longitude}\
&path=weight:3%7Ccolor:red%7Cenc:#{gpx_polyline_data}\
&path=weight:5%7Ccolor:green%7Cenc:#{polyline_data}"

open(mapImageFilename, 'wb') do |file|
  file << open("#{google_maps_query_string}").read
end

# ---------------------------------------

# Get the number of days passed on the trail

start_time = Time.new(2016,4,8)
end_time = Time.now
time_days = TimeDifference.between(start_time, end_time).in_days.ceil 

# ---------------------------------------

ap elevation_points

google_chart = Gchart.line(  :size => '667x200', 
              :title => "PCT 2016 Daily Elevation (MSL feet) Trekked", :title_color => 'FF0000', :title_size => '20',
              :bg => 'efefef',
              :curve_type => 'function',
              :legend => "Day #{time_days} - #{Time.now.strftime("%F")}", :legend_position => 'bottom',
              :axis_with_labels => [['y']],
              :labels => ['MSL ft'],
              :max_value => elevation_points.max + 50,
              :min_value => elevation_points.min - 50,
              :data => elevation_points, 
              :format => 'file', 
              :filename => "./#{elevationImageFilename}")
