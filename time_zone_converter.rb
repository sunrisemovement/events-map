require 'tzinfo'
require 'csv'

MAPPING_CSV = File.join(__dir__, 'time_zones.csv')

module TimeZoneConverter
  def self.windows_to_iana
    @windows_to_iana ||= CSV.read(MAPPING_CSV).each_with_object({}) do |row, h|
      h[row.first] = row.last
    end
  end

  def self.parse_timezone(tz)
    if tz.is_a?(TZInfo::Timezone)
      return tz
    end
    # EveryAction timezone strings are in Windows .NET format, and need to be
    # converted to the IANA standard before the tzinfo library will recognize
    # them
    if windows_to_iana.key?(tz)
      tz = windows_to_iana[tz]
    end
    TZInfo::Timezone.get(tz) rescue nil
  end
end
