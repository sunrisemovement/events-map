class EveryActionClient
  MAX_ITERS = 100

  attr_reader :api_key

  def initialize(api_key)
    @api_key = api_key
  end

  # Request events from the EveryAction API, recursively handling pagination
  def events_request(url=nil, iter=0)
    url ||= "https://api.securevan.com/v4/events?startingAfter=#{Date.today-20}&$expand=onlineforms,locations,codes,shifts,roles,notes"
    resp = HTTParty.get(url,
      basic_auth: {
        username: "sunrise-movement", # NOTE: hardcoding username to Sunrise
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
    @events ||= events_request.map { |e| EveryActionEvent.new(e) }
  end

  def map_entries
    events.select(&:should_appear_on_map?).map(&:map_entry)
  end
end

class EveryActionEvent
  attr_reader :data

  def initialize(data)
    @data = data
  end

  def event_type_blacklist
    ["SunSklData"]
  end

  def should_appear_on_map?
    data["onlineForms"].present? && !event_type_blacklist.include?(event_type) && data['isActive']
  end

  def event_type
    (data["eventType"] || {})["name"]
  end

  def map_entry
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

  def registration_link
    data['onlineForms'].first['url'] rescue nil
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
