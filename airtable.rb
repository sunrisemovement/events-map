require 'airrecord'
require 'dotenv'
require 'pry'
require 'rb-readline'
require 'json'

Dotenv.load
Airrecord.api_key = ENV['AIRTABLE_API_KEY']

def date_parse(d)
  Date.parse(d).to_s
rescue
  nil
end

def query_mapbox(loc)
  resp = JSON.parse(`curl https://api.mapbox.com/geocoding/v5/mapbox.places/#{URI.encode(loc)}.json?access_token=#{ENV['MAPBOX_API_KEY']}`)
  resp['features'].first
end

class EventTypeDictionary < Airrecord::Table
  self.base_key = ENV['AIRTABLE_APP_KEY']
  self.table_name = 'Event Type Dictionary'
end

class Airtable < Airrecord::Table
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
      event_source: 'Airtable',
      event_type: self['event_type'],
      event_title: self['title'],
      description: self['description_text'],
      location_name: self['location_name'],
      registration_link: self['permalink'],
      latitude: self['latitude'],
      longitude: self['longitude']
    }
  end

  def self.map_entries
    all.select(&:should_appear_on_map?).map(&:map_entry)
  end
end
