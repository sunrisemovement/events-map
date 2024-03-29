require_relative 'timeslot'

class EveryActionClient
  attr_reader :api_key, :username

  def initialize(api_key, username: "sunrise-movement")
    # Currently default to "sunrise-movement" for the EA username, because it
    # seems like this will be constant across keys, but may need to update if
    # we add more keys later.
    @username = username
    @api_key = api_key
  end

  def events_request
    # Request upcoming events from the EveryAction API, iteratively handling pagination
    url = "https://api.securevan.com/v4/events?startingAfter=#{Date.today-1}&$expand=onlineforms,locations,codes,shifts,roles,notes"
    res = []
    while url
      resp = HTTParty.get(url,
        basic_auth: {
          username: username,
          password: "#{api_key}|1"
        },
        headers: { "Content-Type" => "application/json" }
      )
      res += resp["items"]
      url = resp["nextPageLink"]
    end
    res
  end

  def events
    # Make events requests (possibly recursively), then wrap each response in a
    # helper object for filtering and formatting
    @events ||= events_request.map { |e| EveryActionEvent.new(e) }
  end

  def visible_events
    events.select(&:should_appear_on_map?)
  end

  def map_entries
    visible_events.map(&:map_entry)
  end
end

class EveryActionEvent
  attr_reader :data

  def initialize(data)
    # Initialize with the raw API response
    @data = data
  end

  def has_hide_code?
    data['codes'].any? { |c| c['name'] == 'hide from map' }
  end

  def should_appear_on_map?
    # Events appear if they're associated with a published online form and if
    # they're listed as active (and also if they're not excluded by event type,
    # but that happens later)
    registration_link.present? && data['isActive'] && !has_hide_code?
  end

  def event_type
    # Get the event type from the response (w/ null-safety)
    (data["eventType"] || {})["name"]
  end

  def timeslots
    [
      Timeslot.new(
        Time.parse(data['startDate']),
        Time.parse(data['endDate']),
        data['dotNetTimeZoneId']
      )
    ]
  end

  def map_entry
    # The main method of this class -- this is the data we surface in the JSON.
    entry = {
      city: address['city'],
      state: address['stateOrProvince'],
      zip_code: address['zipOrPostalCode'],
      location_name: location['name'],
      event_source: 'everyaction',
      event_type: event_type,
      include_on_carousel: true, # by default, EA events are on the carousel
      description: data['description'],
      event_title: data['name'],
      registration_link: registration_link,
      timeslots: timeslots.map(&:as_json),
      latitude: latitude,
      longitude: longitude,
      online_forms: online_forms.map(&:json_entry),
      hub_id: nil
    }
    entry[:end_date] = entry[:timeslots].last[:end_date]
    entry[:start_date] = entry[:timeslots].first[:start_date]
    entry[:end_date_string] = entry[:timeslots].last[:end_date_string]
    entry[:start_date_string] = entry[:timeslots].first[:start_date_string]
    entry
  end

  def online_forms
    # Select online forms that are currently published.
    (data['onlineForms'] || []).
      map{|f| EveryActionOnlineForm.new(f) }.
      select(&:published?)
  end

  def registration_link
    online_forms.first.try(:url)
  end

  def locations
    data["locations"] || []
  end

  def location
    locations.first || {}
  end

  def address
    location['address'] || {}
  end

  def latitude
    (address["geoLocation"] || {})["lat"]
  end

  def longitude
    (address["geoLocation"] || {})["lon"]
  end
end

class EveryActionOnlineForm
  attr_reader :data

  def initialize(data)
    @data = data
  end

  def json_entry
    data
  end

  def published?
    data["status"] == "Published"
  end

  def url
    data["url"]
  end
end
