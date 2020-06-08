require 'httparty'
require 'tzinfo'
require 'pry'

class Timeslot
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

  def finished?
    if end_date
      Time.now > end_date
    else
      Time.now > start_date
    end
  end
end

def equal_emails?(a, b)
  return false unless a.to_s =~ URI::MailTo::EMAIL_REGEXP
  return false unless b.to_s =~ URI::MailTo::EMAIL_REGEXP
  a1 = a.split('@').first
  a2 = a.split('@').last
  b1 = b.split('@').first
  b2 = b.split('@').last
  return false unless a2.downcase == b2.downcase
  return false unless a1.gsub('.','').downcase == b1.gsub('.','').downcase
  true
end

class MobilizeAmericaEvent
  attr_reader :data

  def self.hubs
    @hubs ||= JSON.parse(HTTParty.get(ENV['HUB_JSON_URL']))['map_data'] rescue []
  end

  def contact
    data['contact'] || {}
  end

  def hub_name
    if hub = self.class.hubs.detect{|h| equal_emails?(h['email'], contact['email_address']) }
      puts hub['name']
      hub['name']
    elsif hub = self.class.hubs.detect{|h| h['name'] == contact['name'] }
      puts hub['name']
      hub['name']
    else
      puts data
      puts
    end
  end

  def initialize(data)
    @data = data
  end

  def should_appear?
    data['visibility'] == 'PUBLIC' && data['address_visibility'] == 'PUBLIC' && start_date
  end

  def timeslots
    data['timeslots'].map { |slot| Timeslot.new(slot) }
  end

  def first_timeslot
    timeslots.reject(&:finished?).sort_by(&:start_date).first
  end

  def last_timeslot
    timeslots.reject(&:finished?).sort_by(&:end_date).last
  end

  def tz
    TZInfo::Timezone.get(data['timezone']) rescue nil
  end

  def start_date
    if tz && slot = first_timeslot
      tz.to_local(slot.start_date).strftime('%FT%T%:z')
    end
  end

  def end_date
    if tz && slot = last_timeslot
      tz.to_local(slot.end_date).strftime('%FT%T%:z') rescue tz.to_local(slot.start_date).strftime('%FT%T%:z')
    end
  end

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
      hub_name: hub_name
    }
  end

  def location
    data['location'] || {}
  end

  def latitude
    (location['location'] || {})['latitude']
  end

  def longitude
    (location['location'] || {})['longitude']
  end
end

class MobilizeAmericaRequest
  include HTTParty
  base_uri 'https://api.mobilize.us'

  def initialize(api_key, org_id, page)
    @options = {
      query: {
        page: page
      },
      headers: {
        'Authorization' => "Bearer #{api_key}"
      }
    }

    @events_url = "/v1/organizations/#{org_id}/events"
  end

  def response
    @response ||= self.class.get(@events_url, @options)
  end

  def last_page?
    response['next'].nil?
  end

  def results
    response['data'].map { |r| MobilizeAmericaEvent.new(r) }
  end
end

class MobilizeAmerica
  def initialize(api_key, org_id)
    @api_key = api_key
    @org_id = org_id
  end

  def events(max_pages=100)
    results = []
    max_pages.times do |page|
      req = MobilizeAmericaRequest.new(@api_key, @org_id, page+1)
      results += req.results
      break if req.last_page?
    end
    results.select(&:should_appear?)
  end

  def map_entries
    events.map(&:map_entry)
  end
end
