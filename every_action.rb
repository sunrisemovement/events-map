class EveryActionClient
  attr_reader :api_key

  def initialize(api_key)
    @api_key = api_key
  end

  def map_entries
    events = every_action_events_request(api_key).map { |e| EveryActionEvent.new(e) }
    events.select(&:should_appear_on_map?).map(&:map_entry)
  end
end

class EveryActionEvent
  attr_reader :data

  def initialize(data)
    @data = data
  end

  def allowed_event_types
    ["Hub Meeting",
     "Canvass",
     "Phonebank",
     "Other",
     "Rally/DirectAction",
     "SunSklDefundPolice",
     "SunSklEscuelita",
     "Workshop",
     "Mass Call (Non-SoM)"]
  end

  def should_appear_on_map?
    data["onlineForms"].present? && allowed_event_types.include?(event_type) && data['isActive']
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
      event_source: 'EveryAction',
      event_type: event_type,
      description: data['description'],
      event_title: data['name'],
      registration_link: registration_link,
      start_date: data['startDate'],
      end_date: data['endDate'],
      latitude: latitude,
      longitude: longitude
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

def every_action_events_request(api_key, url=nil)
  url ||= "https://api.securevan.com/v4/events?startingAfter=#{Date.today-1}&$expand=onlineforms,locations,codes,shifts,roles,notes"
  puts url
  resp = HTTParty.get(url,
    basic_auth: {
      username: "sunrise-movement",
      password: "#{api_key}|1"
    },
    headers: { "Content-Type" => "application/json" }
  )
  res = resp["items"]
  if resp["nextPageLink"]
    res += every_action_events_request(api_key, resp["nextPageLink"])
  end
  res
end

def every_action_forms_request(api_key, url=nil)
  url ||= "https://api.securevan.com/v4/onlineActionsForms"
  puts url
  resp = HTTParty.get(url,
    basic_auth: {
      username: "sunrise-movement",
      password: "#{api_key}|1"
    },
    headers: { "Content-Type" => "application/json" }
  )
  res = resp["items"]
  if resp["nextPageLink"]
    res += every_action_forms_request(api_key, resp["nextPageLink"])
  end
  res
end
