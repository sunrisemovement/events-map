require 'aws-sdk-s3'
require 'dotenv'
require 'json'

##
#
# This script uploads the actual event map HTML to S3, where it can be used as
# an iframe. This script can essentially be considered the deploy script for
# the event map.
#
##

# Load environment variables
Dotenv.load

# Initialize our AWS S3 client that lets us upload
# the event map
s3 = Aws::S3::Client.new(
  access_key_id: ENV['AWS_ACCESS_KEY_ID'],
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
  region: ENV['AWS_REGION']
)

# Upload the event map
s3.put_object(
  bucket: ENV['AWS_BUCKET'],
  acl: 'public-read',
  key: 'map.html',
  body: File.read('./event_map.html') # read the HTML from the file
)

# Upload zip codes
s3.put_object(
  bucket: ENV['AWS_BUCKET'],
  acl: 'public-read',
  key: 'zip_codes.json',
  body: File.read('./zip_codes.json')
)
