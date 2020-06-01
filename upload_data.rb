require 'json'
require 'aws-sdk-s3'
require 'dotenv'
require_relative 'airtable'
require_relative 'mobilize_america'

Dotenv.load

s3 = Aws::S3::Client.new(
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: ENV['AWS_REGION']
)

entries = []
entries += Airtable.map_entries

(ENV['MOBILIZE_AMERICA_INFO'] || '').split(',').each do |ma_info|
  api_key, org_id = ma_info.split('_')
  ma_client = MobilizeAmerica.new(api_key, org_id)
  entries += ma_client.map_entries
end

event_type_dict = Hash.new { |h,k| h[k] = {} }

EventTypeDictionary.all.each do |d|
  src_et = d["source_event_type"].to_s.strip.downcase
  [src_et, src_et.gsub(/\s+/, '_')].each do |et|
    if d["exclude_from_map"].to_s == "1"
      event_type_dict[d["Source"]][et] = false
    else
      event_type_dict[d["Source"]][et] = d["map_event_type"]
    end
  end
end

entries = entries.each_with_object([]) do |entry, list|
  src = entry[:event_source]

  if src == 'Airtable'
    list << entry
    next
  end

  src_et = entry[:event_type]
  map_et = event_type_dict[src][src_et.to_s.strip.downcase]
  if map_et === false
    # This event type has specifically been excluded from the map
    puts "Skipping specifically-excluded #{src_et} event type #{src_et.inspect}"
    next
  elsif map_et.nil?
    # This event type is unrecognized; warn but keep it
    puts "Unmapped #{src_et} event type #{src_et.inspect}"
    list << entry
  else
    # This event type has been successfully mapped! :D
    entry[:event_type] = map_et
    list << entry
  end
end

entries.sort_by! { |e| [e[:start_date], e[:city] || e[:location_name] || 'zzz'] }

map_json = JSON.dump({
  updated_at: Time.now.to_s,
  map_data: entries
})

s3.put_object(
  bucket: ENV['AWS_BUCKET'],
  acl: 'public-read',
  key: 'events.json',
  body: map_json
)
