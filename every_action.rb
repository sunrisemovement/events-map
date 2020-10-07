# typed: strict

class EveryActionClient
  extend T::Sig

  sig { returns(String) }
  attr_reader :api_key

  sig { returns(String) }
  attr_reader :username

  sig { params(api_key: String, username: String).void }
  def initialize(api_key, username: "sunrise-movement")
    # Currently default to "sunrise-movement" for the EA username, because it
    # seems like this will be constant across keys, but may need to update if
    # we add more keys later.
    @username = username
    @api_key = api_key

    @events = T.let([], T::Array[EveryActionEvent])
  end

  sig { returns(T::Array[EveryActionEvent]) }
  def events_request
    # Request upcoming events from the EveryAction API, iteratively handling pagination
    url = T.let("https://api.securevan.com/v4/events?startingAfter=#{Date.today-1}&$expand=onlineforms,locations,codes,shifts,roles,notes", T.nilable(String))
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

    res.map { |e| EveryActionEvent.new(e) }
  end

  sig { returns(T::Array[EveryActionEvent]) }
  def events
    # Make events requests (possibly recursively), then wrap each response in a
    # helper object for filtering and formatting
    if @events.empty?
      @events = events_request
    end

    @events
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def map_entries
    # Filter events and get their map entries.
    events.select(&:should_appear_on_map?).map(&:map_entry)
  end
end

class EveryActionEvent
  extend T::Sig

  sig { returns(T::Hash[String, T.untyped]) }
  attr_reader :data

  sig { params(data: T::Hash[String, T.untyped]).void }
  def initialize(data)
    # Initialize with the raw API response
    @data = data
  end

  sig { returns(T::Boolean) }
  def should_appear_on_map?
    # Events appear if they're associated with a published online form and if
    # they're listed as active (and also if they're not excluded by event type,
    # but that happens later)
    registration_link.present? && data['isActive']
  end

  sig { returns(T.nilable(String)) }
  def event_type
    # Get the event type from the response (w/ null-safety)
    (data["eventType"] || {})["name"]
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
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
      featured_image_url: featured_image_url,
      start_date: data['startDate'],
      end_date: data['endDate'],
      latitude: latitude,
      longitude: longitude,
      online_forms: online_forms.map(&:json_entry),
      hub_id: nil
    }
  end

  sig { returns(T::Array[EveryActionOnlineForm]) }
  def online_forms
    # Select online forms that are currently published.
    (data['onlineForms'] || []).
      map{|f| EveryActionOnlineForm.new(f) }.
      select(&:published?)
  end

  sig { returns(T.nilable(String)) }
  def registration_link
    online_forms.first.try(:url)
  end

  sig { returns(T.nilable(String)) }
  def featured_image_url
    online_forms.first.try(:featured_image_url)
  end

  sig { returns(T::Array[T.untyped]) }
  def locations
    data["locations"] || []
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def location
    locations.first || {}
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def address
    location['address'] || {}
  end

  sig { returns(T.nilable(Float)) }
  def latitude
    (address["geoLocation"] || {})["lat"]
  end

  sig { returns(T.nilable(Float)) }
  def longitude
    (address["geoLocation"] || {})["lon"]
  end
end

class EveryActionOnlineForm
  extend T::Sig
  
  sig { returns(T::Hash[String, T.untyped]) }
  attr_reader :data

  sig { params(data: T::Hash[String, T.untyped]).void }
  def initialize(data)
    @data = data
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def json_entry
    data.merge({
      "bannerImagePath" => featured_image_url,
      "description" => description
    })
  end

  sig { returns(T::Boolean) }
  def published?
    data["status"] == "Published"
  end

  sig { returns(T.nilable(String)) }
  def url
    data["url"]
  end

  sig { returns(String) }
  def form_def_url
    # It's not documented in their official API, but @Jared discovered there is
    # a JSON endpoint containing form definition information not included in
    # the limited onlineActionForms response, which in particular includes a
    # featured image URL. This URL can be constructed as follows:
    url.try(
      :sub,
      "https://secure.everyaction.com",
      "https://secure.everyaction.com/v2/Forms"
    )
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def form_def_response
    HTTParty.get(form_def_url, headers: {
      "Content-Type" => "application/json"
    })
  rescue
    {} # Return empty hash in the event this stops working in the future
  end

  sig { returns(T.untyped) }
  def form_def
    @form_def ||= T.let(
      form_def_response,
      T.nilable(T::Hash[T.untyped, T.untyped]),
    )
  end

  sig { returns(T.nilable(String)) }
  def featured_image_url
    form_def["bannerImagePath"]
  end

  sig { returns(T::Array[T.untyped]) }
  def form_elements
    form_def["form_elements"] || []
  end

  sig { returns(T.untyped) }
  def header_element
    # The form definition object includes a header element that looks a lot
    # like a description. This can be used in place of an explicitly given text
    # description for the event.
    form_elements.detect{ |el| el["name"] == "HeaderHtml" && el["type"] == "markup" }
  end

  sig { returns(T.nilable(String)) }
  def description
    # Return the description described above (as an HTML string)
    if header_element
      header_element["markup"]
    end
  end
end
