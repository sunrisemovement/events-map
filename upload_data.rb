require 'json'
require 'aws-sdk-s3'
require_relative 'airtable'
require_relative 'mobilize_america'
require_relative 'action_network'

s3 = Aws::S3::Client.new(
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: ENV['AWS_REGION']
)

at = Airtable.map_entries
ma = MobilizeAmerica.map_entries
an = ActionNetwork.map_entries

entries = at + ma + an
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
