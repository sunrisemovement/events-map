require 'json'
require 'aws-sdk-s3'
require 'dotenv'
require_relative 'hubs_airtable'
require_relative 'events_airtable'
require_relative 'mobilize_america'

Dotenv.load

entries = []

# Load data from the events airtable (barely used)
entries += AirtableEvent.map_entries

# Load data from our two mobilize america accounts (most common use-case)
(ENV['MOBILIZE_AMERICA_INFO'] || '').split(',').each do |ma_info|
  api_key, org_id = ma_info.split('_')
  ma_client = MobilizeAmericaClient.new(api_key, org_id)
  entries += ma_client.event_map_entries
end

# Add event types to the data, mapping them to a common
# user-friendly string using Airtable data
entries = EventTypeDictionary.transform(entries)

entries.sort_by! { |e| [e[:start_date], e[:city] || e[:location_name] || 'zzz'] }

map_json = JSON.dump({
  updated_at: Time.now.to_s,
  map_data: entries
})

s3 = Aws::S3::Client.new(
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: ENV['AWS_REGION']
)

s3.put_object(
  bucket: ENV['AWS_BUCKET'],
  acl: 'public-read',
  key: 'events.json',
  body: map_json
)
