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

  def id
    data['id']
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

# The class wraps "attendance" JSON objects from MA's API, adding helper methods
# to exclude cancelled events
class MobilizeAmericaAttendance
  attr_reader :data # The original data from the API

  def initialize(data)
    @data = data
  end

  def cancelled?
    data['status'] == 'CANCELLED'
  end

  def timeslot_id
    (data['timeslot'] || {})['id']
  end
end

# The class wraps event JSON objects from MA's API, adding helper methods to
# transform them into event JSON for the Sunrise event map.
class MobilizeAmericaEvent
  include Event # Include some platform-agonstic helper methods from event.rb

  attr_reader :data # The original data from the API
  attr_reader :api_key, :org_id # Authentication info for attendance sub-requests

  # Initialize MobilizeAmericaEvents with JSON data from the MA API
  def initialize(data, api_key, org_id)
    @data = data
    @api_key = api_key
    @org_id = org_id
  end

  def id
    data['id']
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

  def format_time(date)
    if tz && date
      tz.to_local(date).strftime('%FT%T%:z')
    end
  end

  # The start date of the first timeslot, in the local time zone, as a string
  def start_date
    format_time(first_timeslot.start_date) if first_timeslot
  end

  # The end date of the last timeslot, in the local timezone, as a string
  # (or the start date of the last timeslot if no end date is provided)
  def end_date
    format_time(last_timeslot.end_date || last_timeslot.start_date) if last_timeslot
  end

  # The main method of this class -- converts the MobilizeAmerica JSON to
  # Sunrise Event Map JSON
  def map_entry
    {
      city: location['locality'],
      state: location['region'],
      address: (location['address_lines'] || []).select{|l| l.size > 0}.join("\n"),
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
      longitude: longitude,
      timeslots: timeslot_map_entries,
      hub_id: hub_id # this method comes from event.rb
    }
  end

  # This method produces a summary of each event timeslot, along with the
  # number of confirmed/registered attendees so far (which we obtain via
  # additional API requests)
  def timeslot_map_entries
    timeslots.reject(&:finished?).map { |slot| {
      start_date: format_time(slot.start_date),
      end_date: format_time(slot.end_date),
      is_full: slot.data['is_full'],
      #instructions: slot.data['instructions'],
      num_registered: attendances.select{|a| a.timeslot_id == slot.id }.length
    }}
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

  # Wrapper around the auxiliary API requests for attendance information
  def attendances_request
    @attendances_request ||= MobilizeAmericaAttendancesRequest.new(@api_key, org_id: @org_id, event_id: id)
  end

  # Attendance information for this event
  def attendances
    attendances_request.results.reject(&:cancelled?)
  end
end

# Superclass for making API requests to mobilize america for a list of
# resources.  Handles pagination and authorization. Uses the `httparty` Ruby
# gem.
class MobilizeAmericaListRequest
  include HTTParty
  base_uri 'https://api.mobilize.us'
  attr_reader :api_key, :page, :options
  MAX_PAGES = 250

  # Event requests require an API key (`api_key`), and are also paginated (`page`)
  def initialize(api_key, page: 1, **options)
    puts "REQUEST"
    @api_key = api_key
    @page = page
    @options = options
  end

  # The base URL for the request (excluding pagination parameters). Define this
  # in subclasses!
  def request_url
    raise NotImplementedError
  end

  # A helper function to map `data` elements to easier-to-handle objects.
  # (Re-)define this in subclasses if desired!
  def results
    data
  end

  # Make the request and cache the response in an instance variable
  def response
    @response ||= self.class.get(request_url, {
      query: { page: page },
      headers: { 'Authorization' => "Bearer #{api_key}" }
    })
  end

  # Check if there are more pages of results
  def last_page?
    response['next'].nil? || page >= MAX_PAGES
  end

  # Instantiate a new request for the next page
  def next_page_request
    self.class.new(api_key, page: page+1, **options) unless last_page?
  end

  # Get data from the response, possibly recursively triggering a request for
  # the next page.
  def data
    @data ||= if last_page?
      response['data']
    else
      response['data'] + next_page_request.data
    end
  end
end

# Wrapper class representing individual /events API requests
# to Mobilize America. 
class MobilizeAmericaEventsRequest < MobilizeAmericaListRequest
  def org_id
    options[:org_id]
  end

  def request_url
    "/v1/organizations/#{org_id}/events"
  end

  def results
    data.map { |r| MobilizeAmericaEvent.new(r, api_key, org_id) }
  end
end

# Wrapper class representing individual attendances API requests
# to Mobilize America. 
class MobilizeAmericaAttendancesRequest < MobilizeAmericaListRequest
  def event_id
    options[:event_id]
  end

  def org_id
    options[:org_id]
  end

  def request_url
    "/v1/organizations/#{org_id}/events/#{event_id}/attendances"
  end

  def results
    data.map { |r| MobilizeAmericaAttendance.new(r) }
  end
end

# Wrapper class for making API requests to Mobilize America for a specific
# organization.
class MobilizeAmericaClient
  def initialize(api_key, org_id)
    @api_key = api_key
    @org_id = org_id
  end

  # Get public, upcoming events for this organization
  def events
    request = MobilizeAmericaEventsRequest.new(@api_key, org_id: @org_id)
    request.results.select(&:should_appear?)
  end

  def event_map_entries
    events.map(&:map_entry)
  end
end
