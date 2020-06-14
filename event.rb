require_relative 'hubs_airtable'

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
