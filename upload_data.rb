require 'json'
require 'aws-sdk-s3'
require_relative 'airtable'
require_relative 'mobilize_america'

s3 = Aws::S3::Client.new(
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: ENV['AWS_REGION']
)

at = Airtable.map_entries
ma = MobilizeAmerica.map_entries

event_type_dict = Hash.new { |h,k| h[k] = {} }

EventTypeDictionary.all.each do |d|
  if d["exclude_from_map"].to_s == "1"
    event_type_dict[d["Source"]][d["source_event_type"].to_s.strip.downcase] = false
  else
    event_type_dict[d["Source"]][d["source_event_type"].to_s.strip.downcase] = d["map_event_type"]
  end
end

ma = ma.each_with_object([]) do |entry, list|
  src_et = entry[:event_type]
  map_et = event_type_dict["MobilizeAmerica"][src_et.to_s.strip.downcase]
  if map_et === false
    # This event type has specifically been excluded from the map
    puts "Skipping specifically-excluded event type #{src_et.inspect}"
    next
  elsif map_et.nil?
    # This event type is unrecognized; warn but keep it
    puts "Unmapped MobilizeAmerica event type #{src_et.inspect}"
    list << entry
  else
    # This event type has been successfully mapped! :D
    entry[:event_type] = map_et
    list << entry
  end
end

entries = at + ma
entries.sort_by! { |e| [e[:start_date], e[:city]] }
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
