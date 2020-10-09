require_relative 'time_zone_converter'

class Timeslot
  attr_reader :start_date, :end_date, :timezone

  def initialize(start_date, end_date, timezone)
    # Parse the API-provided timezone string into a tzinfo object, which can
    # localize our start and end dates appropriately
    @timezone = TimeZoneConverter.parse_timezone(timezone)

    # In the unlikely event we can't parse the timezone properly, fall back to
    # the timezone implied by the UTC offset (which is almost always the same,
    # but does appear to have rare exceptions)
    @timezone ||= Time.find_zone(start_date.utc_offset).tzinfo

    # Convert the start and end date to the right timezone. If the end date
    # isn't provided, set it to the start date.
    @start_date = @timezone.to_local(start_date)
    @end_date = end_date ? @timezone.to_local(end_date) : @start_date
  end

  def finished?
    Time.now > end_date
  end

  def as_json
    {
      start_date: start_date.strftime('%FT%T%:z'),
      end_date: end_date.strftime('%FT%T%:z'),
      timezone_name: timezone.name,
      timezone_abbr: timezone.abbr,
      start_date_string: start_date_string,
      end_date_string: end_date_string
    }
  end

  # Expose some already-user-friendly time strings for API consumer convenience
  def start_date_string
    "#{start_date.strftime("%-m/%-d %-l:%M%P")} #{timezone.abbr}"
  end

  def end_date_string
    "#{end_date.strftime("%-m/%-d %-l:%M%P")} #{timezone.abbr}"
  end
end
