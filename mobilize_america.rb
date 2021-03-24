require 'httparty'
require 'tzinfo'
require_relative 'event'
require_relative 'timeslot'

##
#
# This file contains helpers for getting event data from Mobilize America.
#
##

# The class wraps event JSON objects from MA's API, adding helper methods to
# transform them into event JSON for the Sunrise event map.
class MobilizeAmericaEvent
  include Event # Include some platform-agonstic helper methods from event.rb

  ZIP_COORDS = JSON.parse(File.read(File.join(__dir__, 'zip_codes.json')))

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
  def should_appear_on_map?
    data['visibility'] == 'PUBLIC' && timeslots.any?
  end

  # All of the upcoming timeslots for the events, but as our wrapper objects
  def timeslots
    data['timeslots'].map { |ts|
      Timeslot.new(
        Time.at(ts['start_date']),
        Time.at(ts['end_date'] || ts['start_date']),
        data['timezone']
      )
    }.reject(&:finished?).sort_by(&:start_date)
  end

  # Designate certain hosts to always have events appear / not appear on the
  # carousel, falling back to an email/tag-based rule otherwise.
  def show_on_carousel?
    if EventHost.show_on_carousel?(contact_email)
      true
    elsif EventHost.hide_on_carousel?(contact_email)
      false
    else
      sunrise_national_email? || (national_tag? && !volunteer_host?)
    end
  end

  def sunrise_national_email?
    !!(contact_email.to_s =~ /@sunrisemovement\.org$/)
  end

  def national_tag?
    # Check if event is tagged as national
    (data['tags'] || []).any? { |t| t['name'] == "National Phonebank" || t['name'] == "National Event" }
  end

  def volunteer_host?
    # Check if event is tagged as from a volunteer
    data["created_by_volunteer_host"]
  end

  def campaign_slug
    (data["event_campaign"] || {})["slug"]
  end

  def public_address?
    data['address_visibility'] == 'PUBLIC'
  end

  def location
    data['location'] || {}
  end

  def address
    if public_address?
      (location['address_lines'] || []).select{|l| l.size > 0}.join("\n")
    end
  end

  def zip_code
    location['postal_code']
  end

  def zip_coords
    ZIP_COORDS[zip_code.to_s] if zip_code.present?
  end

  # The latitude of the event (nil-safe)
  def latitude
    if public_address?
      (location['location'] || {})['latitude']
    elsif zip_coords.present?
      zip_coords[0]
    end
  end

  # The longitude of the event (nil-safe)
  def longitude
    if public_address?
      (location['location'] || {})['longitude']
    elsif zip_coords.present?
      zip_coords[1]
    end
  end

  # The main method of this class -- converts the MobilizeAmerica JSON to
  # Sunrise Event Map JSON
  def map_entry
    entry = {
      city: location['locality'],
      state: location['region'],
      address: address,
      zip_code: zip_code,
      event_source: 'mobilize',
      event_type: data['event_type'],
      event_title: data['title'],
      campaign: campaign_slug,
      include_on_carousel: show_on_carousel?,
      description: data['description'],
      location_name: location['venue'],
      featured_image_url: data['featured_image_url'],
      registration_link: data['browser_url'],
      timeslots: timeslots.map(&:as_json),
      latitude: latitude,
      longitude: longitude,
      hub_id: hub_id # this method comes from event.rb
    }
    entry[:end_date] = entry[:timeslots].last[:end_date]
    entry[:start_date] = entry[:timeslots].first[:start_date]
    entry[:end_date_string] = entry[:timeslots].last[:end_date_string]
    entry[:start_date_string] = entry[:timeslots].first[:start_date_string]
    entry
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
    response['data']
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
  def events_request(max_pages=100)
    results = []
    max_pages.times do |page|
      # Repeatedly request events, page by page, until we reach the final page
      # of results (or for some maximum number of pages)
      req = MobilizeAmericaRequest.new(@api_key, @org_id, page+1)
      results += req.results
      break if req.last_page?
    end
    results
  end

  def events
    @events ||= events_request.map { |e| MobilizeAmericaEvent.new(e, @org_id) }
  end

  def visible_events
    events.select(&:should_appear_on_map?)
  end

  def map_entries
    visible_events.map(&:map_entry)
  end
end
