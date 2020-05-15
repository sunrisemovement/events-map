require 'httparty'
require 'dotenv'
require 'tzinfo'
require 'pry'

Dotenv.load

MA_SUNRISE_ID = ENV['MOBILIZE_AMERICA_ORG_ID']
MA_SUNRISE_KEY = ENV['MOBILIZE_AMERICA_API_KEY']

class Timeslot
  attr_reader :data

  def initialize(data)
    @data = data
  end

  def start_date
    Time.at(data['start_date'])
  end

  def end_date
    Time.at(data['end_date']) if data['end_date']
  end

  def finished?
    if end_date
      Time.now > end_date
    else
      Time.now > start_date
    end
  end
end

class MobilizeAmericaEvent
  attr_reader :data

  def initialize(data)
    @data = data
  end

  def should_appear?
    data['visibility'] == 'PUBLIC' && data['address_visibility'] == 'PUBLIC' && start_date
  end

  def timeslots
    data['timeslots'].map { |slot| Timeslot.new(slot) }
  end

  def next_timeslot
    timeslots.reject(&:finished?).sort_by(&:start_date).first
  end

  def tz
    TZInfo::Timezone.get(data['timezone']) rescue nil
  end

  def start_date
    if tz && slot = next_timeslot
      tz.to_local(slot.start_date).strftime('%FT%T%:z')
    end
  end

  def end_date
    if tz && slot = next_timeslot
      tz.to_local(slot.end_date).strftime('%FT%T%:z') rescue nil
    end
  end

  def map_entry
    {
      city: location['locality'],
      state: location['region'],
      address: location['address_lines'].select{|l| l.size > 0}.join("\n"),
      zip_code: location['postal_code'],
      event_source: 'MobilizeAmerica',
      event_type: data['event_type'],
      event_title: data['title'],
      description: data['description'],
      location_name: location['venue'],
      registration_link: data['browser_url'],
      start_date: start_date,
      end_date: end_date,
      latitude: latitude,
      longitude: longitude
    }
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
