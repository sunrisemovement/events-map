# typed: false
require_relative 'hubs_airtable'

# This is a module that is included in specific event wrapper classes -- it's
# main use is to provide helpers for finding associated hubs. Most of the
# business logic for that lives in hubs_airtable.rb, though.
module Event
  def map_entry
    raise NotImplementedError
  end

  def contact_email
    raise NotImplementedError
  end

  def contact_name
    raise NotImplementedError
  end

  def hub_id
    hub.try(:id)
  end

  def hub
    @hub ||= (
      Hub.match_email(contact_email) ||
      Hub.match_name(contact_name)
    )
  end
end
