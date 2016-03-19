#!/usr/bin/env ruby

require 'active_support'
require 'active_support/core_ext'
require 'nokogiri'
require 'awesome_print'
require 'curb'
require 'json/ext'
require 'wannabe_bool'
require 'json'
require 'yaml'
require 'twilio-ruby'

unless ARGV[0] and ARGV[1]
  puts "\nYou need to the number of days and the debugging flag\n"
  puts "Usage: delorme-kml-parse.rb [DAYS] [VERBOSE]\n"
  exit
end

start_date = ARGV[0].to_i.days.ago.utc.iso8601
verbose = ARGV[1].to_b

# ---------------------------------------

config = YAML.load_file("config.yml")
config["config"].each { |key, value| instance_variable_set("@#{key}", value) }

# ---------------------------------------

c = Curl::Easy.new("https://share.delorme.com/feed/share/#{@DELORME_INREACH_MAPSHARE}?d1=#{start_date}")
c.http_auth_types = :basic
c.username = @DELORME_INREACH_MAPSHARE_ACCOUNT
c.password = @DELORME_INREACH_MAPSHARE_PASSWORD
c.perform
kml = c.body_str
kml_doc = Nokogiri::XML(kml)
puts "Errors: #{kml_doc.errors}" unless kml_doc.errors.empty?
# ap kml_doc

# ---------------------------------------

kml_hash = Hash.from_xml(kml_doc.to_s)
# ap kml_hash if verbose

if kml_hash["kml"]["Document"]["Folder"].present?
  kml_points = kml_hash["kml"]["Document"]["Folder"]["Placemark"].reject{|ind| ind["TimeStamp"] == nil}.collect{|ind| {"point" => {"latitude" => ind["ExtendedData"]["Data"][8]["value"].to_f, "longitude" => ind["ExtendedData"]["Data"][9]["value"].to_f, "timestamp" => ind["TimeStamp"]["when"].to_datetime}}}
  polyline_points = kml_points.reverse.collect{|ind| [ind["point"]["latitude"], ind["point"]["longitude"]]}
  location_latitude = polyline_points.first[0] unless polyline_points.empty?
  location_longitude = polyline_points.first[1] unless polyline_points.empty?

  # Create Point 
  last_point_hash = {"last_point" => {"latitude" => location_latitude, "longitude" => location_longitude}}
  puts last_point_hash.to_json if verbose
  puts kml_points.to_json if verbose
else
  kml_points = []
  puts "No new waypoints found!" if verbose
  abort
end

# ---------------------------------------

client = Twilio::REST::Client.new @TWILIO_ACCOUNT_SID, @TWILIO_AUTH_TOKEN

sms_recipient_list = JSON.parse(@SMS_RECIPIENTS)
 
sms_recipient_list.each do |key, value|
  r = client.account.messages.create(
    :from => @TWILIO_NUMBER,
    :to => key,
    :body => "Location #{last_point_hash}"
  )
  ap r.status if verbose
  puts "Sent message to #{value}"
end