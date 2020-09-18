require 'httparty'
require 'tzinfo'
require_relative 'event'

##
#
# This file contains helpers for getting event data from Mobilize America.
#
##

# The class wraps "timeslot" JSON objects from MA's API, adding helper methods
# to decide whether an event has finished
class MobilizeAmericaTimeslot
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

  # An event is finished if all of its dates (start and end) are in the past
  def finished?
    if end_date
      Time.now > end_date
    else
      Time.now > start_date
    end
  end
end

# The class wraps event JSON objects from MA's API, adding helper methods to
# transform them into event JSON for the Sunrise event map.
class MobilizeAmericaEvent
  include Event # Include some platform-agonstic helper methods from event.rb

  attr_reader :data # The original data from the API
  attr_reader :org_id # The mobilize america organization id

  # Initialize MobilizeAmericaEvents with JSON data from the MA API
  def initialize(data, org_id)
    @data = data
    @org_id = org_id
  end

  # Events should appear if they're marked as public, and if they're upcoming.
  # Note that we just check the presence of `start_date` to determine if the
  # events are upcoming because it's coming from the `first_timeslot` object,
  # which is only present if there is at least one non-finished timeslot.
  def should_appear?
    data['visibility'] == 'PUBLIC' && data['address_visibility'] == 'PUBLIC' && start_date
  end

  # All of the timeslots for the events, but as our wrapper objects
  def timeslots
    data['timeslots'].map { |slot| MobilizeAmericaTimeslot.new(slot) }
  end

  # The earliest-starting timeslot which isn't already finished
  def first_timeslot
    timeslots.reject(&:finished?).sort_by(&:start_date).first
  end

  # The latest-ending timeslot which isn't already finished
  def last_timeslot
    timeslots.reject(&:finished?).sort_by(&:end_date).last
  end

  # The timezone for the event. Important to make sure events appear in local
  # time.
  def tz
    TZInfo::Timezone.get(data['timezone']) rescue nil
  end

  # The start date of the first timeslot, in the local time zone, as a string
  def start_date
    if tz && slot = first_timeslot
      tz.to_local(slot.start_date).strftime('%FT%T%:z')
    end
  end

  # The end date of the last timeslot, in the local timezone, as a string
  # (or the start date of the last timeslot if no end date is provided)
  def end_date
    if tz && slot = last_timeslot
      tz.to_local(slot.end_date).strftime('%FT%T%:z') rescue tz.to_local(slot.start_date).strftime('%FT%T%:z')
    end
  end

  # The national site needs to distinguish national Sunrise events from local /
  # hub-sponsored Sunrise events.  Most national events are on EveryAction, but
  # some are on Mobilize. Currently, these are just within a single
  # organization (which we can set by environment variable), and only hosted by
  # @sunrisemovement.org emails.
  def is_national
    return false unless natl_id = ENV['NATIONAL_MOBILIZE_ORG_ID']
    return false unless org_id.to_s == natl_id.to_s
    return false unless contact_email.to_s =~ /@sunrisemovement\.org$/
    true
  end

  # The main method of this class -- converts the MobilizeAmerica JSON to
  # Sunrise Event Map JSON
  def map_entry
    {
      city: location['locality'],
      state: location['region'],
      address: (location['address_lines'] || []).select{|l| l.size > 0}.join("\n"),
      zip_code: location['postal_code'],
      event_source: 'mobilize',
      event_type: data['event_type'],
      event_title: data['title'],
      is_national: is_national,
      description: data['description'],
      location_name: location['venue'],
      registration_link: data['browser_url'],
      start_date: start_date,
      end_date: end_date,
      latitude: latitude,
      longitude: longitude,
      hub_id: hub_id # this method comes from event.rb
    }
  end

  def location
    data['location'] || {}
  end

  # The latitude of the event (nil-safe)
  def latitude
    (location['location'] || {})['latitude']
  end

  # The longitude of the event (nil-safe)
  def longitude
    (location['location'] || {})['longitude']
  end

  def contact
    data['contact'] || {}
  end

  # The email of the event contact person (used for mapping to hubs)
  def contact_email
    contact['email_address']
  end

  # The name of the event contact person (used for mapping to hubs)
  def contact_name
    contact['name']
  end
end

# Wrapper class representing individual /events API requests
# to Mobilize America. Uses the `httparty` Ruby gem.
class MobilizeAmericaRequest
  include HTTParty
  base_uri 'https://api.mobilize.us'

  # Event requests are specific to an organization (`org_id`), require an API
  # key (`api_key`), and are also paginated (`page`)
  def initialize(api_key, org_id, page)
    @options = {
      query: {
        page: page
      },
      headers: {
        'Authorization' => "Bearer #{api_key}"
      }
    }

    @org_id = org_id

    @events_url = "/v1/organizations/#{org_id}/events"
  end

  # Make the request and cache the response in an instance variable
  def response
    @response ||= self.class.get(@events_url, @options)
  end

  # Check if there are more pages of results for this organization
  def last_page?
    response['next'].nil?
  end

  # Convert all of the events in the JSON response to our wrapper object
  def results
    response['data'].map { |r| MobilizeAmericaEvent.new(r, @org_id) }
  end
end

# Wrapper class for making API requests to Mobilize America for a specific
# organization.
class MobilizeAmericaClient
  def initialize(api_key, org_id)
    @api_key = api_key
    @org_id = org_id
  end

  # Get events for this organization
  def events(max_pages=100)
    results = []
    max_pages.times do |page|
      # Repeatedly request events, page by page, until we reach the final page
      # of results (or for some maximum number of pages)
      req = MobilizeAmericaRequest.new(@api_key, @org_id, page+1)
      results += req.results
      break if req.last_page?
    end
    # Hide the events which are not public or have already happened
    results.select(&:should_appear?)
  end

  def event_map_entries
    events.map(&:map_entry)
  end
end
