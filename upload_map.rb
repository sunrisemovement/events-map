require 'aws-sdk-s3'
require 'dotenv'
require 'json'

Dotenv.load

s3 = Aws::S3::Client.new(
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: ENV['AWS_REGION']
)

s3.put_object(
  bucket: ENV['AWS_BUCKET'],
  acl: 'public-read',
  key: 'map.html',
  body: File.read('./event_map.html')
)
