require 'active_support'
require 'active_support/core_ext'
require 'nokogiri'
require 'awesome_print'
require 'curb'
require 'json/ext'

start_date = "2016-3-15T11:41:26Z"

# ---------------------------------------

c = Curl::Easy.new("https://share.delorme.com/feed/share/#{ENV['DELORME_INREACH_MAPSHARE']}?d1=#{start_date}")
c.http_auth_types = :basic
c.username = ENV['DELORME_INREACH_MAPSHARE_ACCOUNT']
c.password = ENV['DELORME_INREACH_MAPSHARE_PASSWORD']
c.perform
kml = c.body_str
kml_doc = Nokogiri::XML(kml)
puts "Errors: #{kml_doc.errors}" unless kml_doc.errors.empty?
# ap kml_doc

# ---------------------------------------

kml_hash = Hash.from_xml(kml_doc.to_s)
# ap kml_hash

kml_points = []

kml_points = kml_hash["kml"]["Document"]["Folder"]["Placemark"].reject{|ind| ind["TimeStamp"] == nil}.collect{|ind| [ind["ExtendedData"]["Data"][8]["value"].to_f, ind["ExtendedData"]["Data"][9]["value"].to_f, ind["TimeStamp"]["when"].to_datetime]} if kml_hash["kml"]["Document"]["Folder"].present?

ap polyline_points = kml_points.reverse.collect{|ind| [ind[0],ind[1]]}
ap location_latitude = polyline_points.first[0] unless polyline_points.empty?
ap location_longitude = polyline_points.first[1] unless polyline_points.empty?
