require 'json'
require 'aws-sdk-s3'
require_relative 'airtable'
require_relative 'mobilize_america'

s3 = Aws::S3::Client.new(
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: ENV['AWS_REGION']
)

entries = Airtable.map_entries + MobilizeAmerica.map_entries
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
