# typed: false
require 'sinatra'

PAGE = File.read('./event_map.html')
USER = ENV.fetch('USERNAME', 'admin')
PASS = ENV.fetch('PASSWORD', 'admin')

use Rack::Auth::Basic, "Restricted Area" do |user, pass|
  user == USER && pass == PASS
end

get '/' do
  PAGE
end
