require 'json'
require 'aws-sdk-s3'
require 'dotenv'
require_relative 'hubs_airtable'
require_relative 'events_airtable'
require_relative 'mobilize_america'

##
#
# This script triggers API gets events data from all of our event sources
# (mobilize america, events airtable, etc), associates them with hubs, and
# converts them all to a common JSON form. Then it uploads the result to S3,
# where it's stored in a public file that can be accessed by Javascript in
# event_map.html.
#
##

# Load environment variables (API keys, etc)
Dotenv.load

# Array to store the event objects
entries = []

# Load data from the events airtable (barely used)
entries += AirtableEvent.map_entries

# Load event data from our two mobilize america accounts (most common use-case)
(ENV['MOBILIZE_AMERICA_INFO'] || '').split(',').each do |ma_info|
  api_key, org_id = ma_info.split('_')
  ma_client = MobilizeAmericaClient.new(api_key, org_id)
  entries += ma_client.event_map_entries
end

# Add event types to the data, mapping them to a common
# user-friendly string using Airtable data
entries = EventTypeDictionary.transform(entries)

# Sort the events by their start date, using location as a backup
entries.sort_by! { |e| [e[:start_date], e[:city] || e[:location_name] || 'zzz'] }

# Convert everything to JSON, with the current timestamp (to help with
# debugging)
map_json = JSON.dump({
  updated_at: Time.now.to_s,
  map_data: entries
})

# Initialize our AWS S3 client that lets us upload
# the event data
s3 = Aws::S3::Client.new(
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: ENV['AWS_REGION']
)

# Upload the event data
s3.put_object(
  bucket: ENV['AWS_BUCKET'],
  acl: 'public-read',
  key: 'events.json',
  body: map_json
)
