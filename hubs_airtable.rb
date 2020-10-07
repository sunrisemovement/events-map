# typed: true
require 'airrecord'
require 'dotenv'
require 'set'
require 'active_support'
require 'active_support/core_ext'

##
#
# This file contains helpers for requesting hub information from the Hub
# Tracking Airtable, written using the `airrecord` gem.
#
# The only context in which this is used is for determining the Airtable ID of
# the hub that created the event, which is used in Sunrise Hub Microsites to
# render a list of events created by that hub. It's not used directly in the
# event map as of July 4th, 2020, though it theoretically could be.
#
##

# Load environment variables that tell us the API key and app id which will let
# us access the Hub Tracking Airtable.
Dotenv.load
Airrecord.api_key = ENV['AIRTABLE_API_KEY']

# Wrapper class around hub leaders
class Leader < Airrecord::Table
  self.base_key = ENV['HUBHUB_APP_KEY']
  self.table_name = 'Hub Leaders'

  # Skip leaders that are marked as deleted
  def deleted?
    self['Deleted by Hubhub?']
  end

  def self.visible
    @visible ||= all.reject(&:deleted?)
  end
end

# Wrapper class around hubs
class Hub < Airrecord::Table
  self.base_key = ENV['HUBHUB_APP_KEY']
  self.table_name = 'Hubs'

  has_many :hub_leaders, class: 'Leader', column: 'Hub Leaders'

  # A hub only actually appears on the map (even if it's marked as Map?) if
  # it's active and has the minimum necessary information to render the map
  # card and marker.
  def should_appear_on_map?
    return false if self['Activity'] == 'Inactive'
    return false unless self['Map?'] == true
    return false unless self['Latitude'] && self['Longitude']
    return false unless self['City'] && self['Name']
    true
  end

  def leader_ids
    # Return the Airtable IDs of the hub's leaders
    self['Hub Leaders'] || []
  end

  def self.standardize_email(email)
    # Standarize emails, ensuring case-insensitive comparisons with local part
    # dots ignored.
    local_part, domain = email.split('@')
    "#{local_part.downcase.gsub('.', '')}@#{domain.downcase}"
  end

  def self.standardize_name(name)
    # Compare names after downcasing and whitespace stripping
    name.to_s.strip.downcase
  end

  def self.visible
    # Return a list of hubs that are allowed to appear on the map -- don't want
    # to consider inactive hubs or hubs that haven't fully incorporated yet.
    @visible ||= all.select(&:should_appear_on_map?)
  end

  def self.by_email
    @by_email ||= begin
      # Get all hubs and leaders
      hubs = self.visible
      leaders = Leader.visible

      # Construct a top-level map to leaders to save on API queries
      leaders_by_id = leaders.each_with_object({}) do |lead, h|
        h[lead.id] = lead
      end

      # Construct a mapping that will associate each email with an array of
      # hubs. There should be only one, but using an array allows us to verify
      # this.
      mapping = Hash.new{|h,k| h[k] = Set.new}

      # Loop through hubs, get all associated emails, add mappings for each
      hubs.each do |hub|
        emails = [hub['Email'], hub['Custom Map Email']]
        emails += hub.leader_ids
          .map { |id| leaders_by_id[id] }.compact
          .map { |lead| lead['Email'] }
        emails.select! { |e| e.to_s =~ URI::MailTo::EMAIL_REGEXP }
        emails.map! { |e| self.standardize_email(e) }
        emails.each { |e| mapping[e] << hub }
      end

      # Return the generated mapping from the block
      mapping
    end
  end

  def self.by_name
    @by_name ||= begin
      # Construct a mapping that will associate each email with a set of
      # hubs. There should be only one, but using an array allows us to verify
      # this.
      mapping = Hash.new{|h,k| h[k] = Set.new}

      # Loop through hubs, add entry for name
      self.visible.each do |hub|
        mapping[self.standardize_name(hub['Name'])] << hub
      end

      # Return the generated mapping from the block
      mapping
    end
  end

  def self.match_email(email)
    return unless email.to_s =~ URI::MailTo::EMAIL_REGEXP
    hubs = self.by_email[self.standardize_email(email)]
    case hubs.size
    when 0
      nil
    when 1
      hubs.first
    else
      puts "Warning: for email #{email}, found multiple hubs #{hubs.map(&:id)}"
      nil
    end
  end

  def self.match_name(name)
    return unless self.standardize_name(name).present?
    hubs = self.by_name[self.standardize_name(name)]
    case hubs.size
    when 0
      nil
    when 1
      hubs.first
    else
      puts "Warning: for name #{name}, found multiple hubs #{hubs.map(&:id)}"
      nil
    end
  end
end
