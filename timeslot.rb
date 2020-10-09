require_relative 'time_zone_converter'

class Timeslot
  attr_reader :start_date, :end_date, :timezone

  def initialize(start_date, end_date, timezone)
    @timezone = TimeZoneConverter.parse_timezone(timezone)
    @timezone ||= Time.find_zone(start_date.utc_offset).tzinfo
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

  def start_date_string
    "#{start_date.strftime("%-m/%-d %-l:%M%P")} #{timezone.abbr}"
  end

  def end_date_string
    "#{end_date.strftime("%-m/%-d %-l:%M%P")} #{timezone.abbr}"
  end
end
