class EveryActionClient
  MAX_ITERS = 100

  attr_reader :api_key, :username

  def initialize(api_key, username: "sunrise-movement")
    # Initialize the client with an API key and an optional username,
    # defaulting to Sunrise
    @username = username
    @api_key = api_key
  end

  def events_request(url=nil, iter=0)
    # Request upcoming events from the EveryAction API, recursively handling pagination
    url ||= "https://api.securevan.com/v4/events?startingAfter=#{Date.today-1}&$expand=onlineforms,locations,codes,shifts,roles,notes"
    resp = HTTParty.get(url,
      basic_auth: {
        username: username,
        password: "#{api_key}|1"
      },
      headers: { "Content-Type" => "application/json" }
    )
    res = resp["items"]
    if resp["nextPageLink"] && iter < MAX_ITERS
      res += events_request(resp["nextPageLink"], iter+1)
    end
    res
  end

  def events
    # Make events requests (possibly recursively), then wrap each response in a
    # helper object for filtering and formatting
    @events ||= events_request.map { |e| EveryActionEvent.new(e) }
  end

  def map_entries
    # Filter events and get their map entries.
    events.select(&:should_appear_on_map?).map(&:map_entry)
  end
end

class EveryActionEvent
  attr_reader :data

  def initialize(data)
    # Initialize with the raw API response
    @data = data
  end

  def should_appear_on_map?
    # Events appear if they're associated with a published online form and if
    # they're listed as active (and also if they're not excluded by event type,
    # but that happens later)
    registration_link.present? && data['isActive']
  end

  def event_type
    # Get the event type from the response (w/ null-safety)
    (data["eventType"] || {})["name"]
  end

  def map_entry
    # The main method of this class -- this is the data we surface in the JSON.
    {
      city: address['city'],
      state: address['stateOrProvince'],
      zip_code: address['zipOrPostalCode'],
      location_name: location['name'],
      event_source: 'everyaction',
      event_type: event_type,
      is_national: true,
      description: data['description'],
      event_title: data['name'],
      registration_link: registration_link,
      start_date: data['startDate'],
      end_date: data['endDate'],
      latitude: latitude,
      longitude: longitude,
      online_forms: data['onlineForms'],
      hub_id: nil
    }
  end

  def online_forms
    # Select online forms that are currently published.
    (data['onlineForms'] || []).select{|f| f["status"] == "Published" }
  end

  def registration_link
    # Get the registration link for the first online form.
    online_forms.first['url'] rescue nil
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
