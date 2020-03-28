require 'httparty'
require 'dotenv'
require 'tzinfo'
require 'pry'

Dotenv.load

MA_SUNRISE_ID = ENV['MOBILIZE_AMERICA_ORG_ID']
MA_SUNRISE_KEY = ENV['MOBILIZE_AMERICA_API_KEY']

class MobilizeAmericaEvent
  attr_reader :data

  def initialize(data)
    @data = data
  end

  def should_appear?
    data['visibility'] == 'PUBLIC' && data['address_visibility'] == 'PUBLIC'
  end

  def timeslots
    data['timeslots'].map { |slot| {
      start_date: Time.at(slot['start_date']),
      end_date: (Time.at(slot['end_date']) if slot['end_date'])
    }}.select { |slot|
      (slot[:end_date] || slot[:start_date]) >= Time.now
    }
  end

  def event_type
    data['event_type']
  end

  def map_entry
    entry = {
      city: location['locality'],
      state: location['region'],
      address: location['address_lines'].select{|l| l.size > 0}.join("\n"),
      zip_code: location['postal_code'],
      event_type: 'MobilizeAmerica Event',#event_type,
      event_title: data['title'],
      description: data['description'],
      location_name: location['venue'],
      registration_link: data['browser_url'],
      latitude: latitude,
      longitude: longitude
    }
    if slot = timeslots.first
      tz = TZInfo::Timezone.get(data['timezone'])
      start_date = tz.to_local(slot[:start_date])
      end_date = tz.to_local(slot[:end_date]) rescue nil
      entry[:start_date] = start_date.strftime('%FT%T%:z')
      entry[:end_date] = end_date.strftime('%FT%T%:z') rescue ''
    end
    entry
  end

  def location
    data['location']
  end

  def latitude
    location['location']['latitude']
  end

  def longitude
    location['location']['longitude']
  end
end

class MobilizeAmericaRequest
  include HTTParty
  base_uri 'https://api.mobilize.us'

  def initialize(page)
    @options = {
      query: {
        page: page
      },
      headers: {
        'Authorization' => "Bearer #{MA_SUNRISE_KEY}"
      }
    }
  end

  def response
    @response ||= self.class.get("/v1/organizations/#{MA_SUNRISE_ID}/events", @options)
  end

  def last_page?
    response['next'].nil?
  end

  def results
    response['data'].map { |r| MobilizeAmericaEvent.new(r) }
  end
end

class MobilizeAmerica
  def self.events(max_pages=100)
    results = []
    max_pages.times do |page|
      req = MobilizeAmericaRequest.new(page+1)
      results += req.results
      break if req.last_page?
    end
    results.select(&:should_appear?)
  end

  def self.map_entries
    self.events.map(&:map_entry)
  end
end
