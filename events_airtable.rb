require 'airrecord'
require 'dotenv'
require 'pry'
require 'rb-readline'
require 'json'
require_relative 'event'

Dotenv.load
Airrecord.api_key = ENV['AIRTABLE_API_KEY']

# Safely try to transform a data string into a standard format
def date_parse(d)
  Date.parse(d).to_s
rescue
  nil
end

# Use mapbox to generate latitudes and longitudes for Airtable events that
# are missing them.
def query_mapbox(loc)
  resp = JSON.parse(`curl https://api.mapbox.com/geocoding/v5/mapbox.places/#{URI.encode(loc)}.json?access_token=#{ENV['MAPBOX_API_KEY']}`)
  resp['features'].first
end

class EventTypeDictionary < Airrecord::Table
  self.base_key = ENV['AIRTABLE_APP_KEY']
  self.table_name = 'Event Type Dictionary'

  def self.mapping
    # Construct a hash of (source event type => user-friendly name) using
    # the data provided in the Event Map and Management Airtable
    dict = Hash.new { |h,k| h[k] = {} }

    all.each do |d|
      src_et = d["source_event_type"].to_s.strip.downcase
      [src_et, src_et.gsub(/\s+/, '_')].each do |et|
        src = d["Source"].to_s.downcase
        src_et = et.to_s.downcase
        if d["exclude_from_map"].to_s == "1"
          dict[src][src_et] = false
        else
          dict[src][src_et] = d["map_event_type"]
        end
      end
    end

    dict
  end

  def self.transform(entries)
    # Transform event entries using the above mapping -- importantly,
    # using that data to skip events with types we want to keep private.
    dict = self.mapping
    entries.each_with_object([]) do |entry, list|
      src = entry[:event_source].to_s.downcase
      src_et = entry[:event_type].to_s.strip.downcase
      map_et = dict[src][src_et.to_s.strip.downcase]

      if src == 'airtable'
        # Airtable events that have made it this far are always included
        # and have the right event type
        list << entry
        next
      end

      if map_et === false
        # This event type has specifically been excluded from the map
        puts "Skipping specifically-excluded #{src} event type #{entry[:event_type].inspect}"
        next
      elsif map_et.nil?
        # This event type is unrecognized; warn but keep it
        puts "Unmapped #{src} event type #{entry[:event_type].inspect}"
        list << entry
      else
        # This event type has been successfully mapped! :D
        entry[:event_type] = map_et
        list << entry
      end
    end
  end
end

# Wrapper class for Airtable events
class AirtableEvent < Airrecord::Table
  include Event

  self.base_key = ENV['AIRTABLE_APP_KEY']
  self.table_name = 'Events'

  def upcoming?
    return true if Date.parse(self['start_at']) >= Date.today
    return true if Date.parse(self['end_at']) >= Date.today
    false
  rescue
    false
  end

  def has_lat_lng?
    self['latitude'] && self['longitude']
  end

  def should_appear_on_map?
    return false unless upcoming?
    return false unless self['Approved?']
    return false if self['private']
    return true if has_lat_lng?
    populate_lat_lng!
    has_lat_lng?
  end

  def computed_lat_lng
    # Query mapbox using the helper function at the top of this file
    return nil, nil unless self['zip_code']
    loc_full = "#{self['address']} #{self['zip_code']} #{self['city']}, #{self['state']}"
    loc_part = "#{self['zip_code']} #{self['city']}, #{self['state']}"
    feature = query_mapbox(loc_full) || query_mapbox(loc_part)
    lng, lat = feature['center']
    return lat, lng
  rescue
    return nil, nil
  end

  def populate_lat_lng!
    # Use the queried data to populate latitude and longitude, and save it
    # so we don't have to query mapbox again (and so that it can be
    # manually updated if necessary)
    raise if has_lat_lng?
    return unless ENV['MAPBOX_API_KEY']
    lat, lng = computed_lat_lng
    return unless lat && lng
    self['latitude'] = lat
    self['longitude'] = lng
    save
  end

  def map_entry
    return {
      start_date: self['start_at'],
      end_date: self['end_at'],
      city: self['city'],
      state: self['state'],
      address: self['address'],
      zip_code: self['zip_code'],
      event_source: 'airtable',
      event_type: self['event_type'],
      event_title: self['title'],
      description: self['description_text'],
      location_name: self['location_name'],
      registration_link: self['permalink'],
      latitude: self['latitude'],
      longitude: self['longitude'],
      is_national: false,
      hub_id: hub_id
    }
  end

  def contact_email
    self['host_email']
  end

  def contact_name
    "#{self['host_first_name']} #{self['host_last_name']}"
  end

  def self.map_entries
    all.select(&:should_appear_on_map?).map(&:map_entry)
  end
end
