# typed: true
require 'httparty'
require 'dotenv'

###
# This file contains helpers for getting event data from ActionNetwork.
#
# Note that ActionNetwork has been phased out, so this code is no longer in
# active use.
###

# Load environment variables (used to get API key)
Dotenv.load

# Wrapper class around the ActionNetwork Event JSON object that provides helper
# methods for transforming it into JSON for the event map
class ActionNetworkEvent
  attr_reader :data

  def initialize(data)
    @data = data
  end

  def start_time
    Time.parse(data['start_date'])
  end

  def is_public?
    data['visibility'] == 'public'
  end

  # Events should appear if they're public and if they haven't already happened
  def should_appear?
    !data['start_date'].nil? && is_public? && Date.parse(data['start_date']) >= Date.today
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

  def description
    if desc = data['description']
      desc.gsub!(/<\/?[^>]*>/, "")
      if desc.length > 140
        "#{desc[0..137]}..."
      else
        desc
      end
    end
  end

  def map_entry
    {
      city: location['locality'],
      state: location['region'],
      address: (location['address_lines'] || []).select{|l| l.size > 0}.join("\n"),
      zip_code: location['postal_code'],
      event_type: 'ActionNetwork Event',
      event_title: data['title'],
      description: description,
      location_name: location['venue'],
      registration_link: data['browser_url'],
      latitude: latitude,
      longitude: longitude,
      start_date: data['start_date']
    }
  end
end

# Wrapper class around the actual request to the ActionNetwork API. Uses the
# 'httparty' library.
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
    response["_embedded"]["osdi:events"].map { |e| ActionNetworkEvent.new(e) }
  end
end

# Wrapper class around ActionNetwork overall. This makes requests to the
# /events?page=X endpoint until we reach the last page.
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
