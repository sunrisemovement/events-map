require 'httparty'
require 'dotenv'
require 'pry'

Dotenv.load

class ActionNetworkEvent
  attr_reader :data

  def initialize(data)
    @data = data
  end

  def start_time
    Time.parse(data['start'])
  end

  def is_public?
    data['visibility'] == 'public'
  end

  def should_appear?
    is_public?# && start_time >= Date.today
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

  def map_entry
    {
      city: location['locality'],
      state: location['region'],
      address: location['address_lines'].select{|l| l.size > 0}.join("\n"),
      zip_code: location['postal_code'],
      event_type: 'ActionNetwork Event',
      event_title: data['title'],
      description: data['description'],
      location_name: location['venue'],
      registration_link: data['browser_url'],
      latitude: latitude,
      longitude: longitude,
      start_date: data['start_date']
    }
  end
end

class ActionNetworkRequest
  include HTTParty
  base_uri 'https://actionnetwork.org'

  def initialize(page)
    @page = page
    @options = {
      query: {
        page: page,
        per_page: 25
      },
      headers: {
        'OSDI-API-Token' => ENV['ACTION_NETWORK_API_KEY']
      }
    }
  end

  def response
    @response ||= self.class.get("/api/v2/events", @options)
  end

  def last_page?
    @page >= response['total_pages']
  end

  def results
    r = response["_embedded"]["osdi:events"].map { |e| ActionNetworkEvent.new(e) }
    binding.pry
    r
  end
end

class ActionNetwork
  def self.events(max_pages=100)
    results = []
    max_pages.times do |page|
      req = ActionNetworkRequest.new(page+1)
      results += req.results
      break if req.last_page?
    end
    results.select(&:should_appear?)
  end

  def self.map_entries
    self.events.map(&:map_entry)
  end
end
