# Sunrise Events Map

This repository contains code for aggregating Sunrise movement events from various sources (Airtable, Mobilize America, etc) and converting them into a JSON payload that powers the [Sunrise event map](https://www.sunrisemovement.org/events). It also contains the frontend code for the map itself.

## Repository Structure

Here are the main files used in this repository:

- [`upload_data.rb`](./upload_data.rb) contains the top-level script for fetching, processing, and uploading event data. This is run every 10 minutes by an app deployed on [Heroku](https://www.heroku.com/).
- [`upload_map.rb`](./upload_map.rb) contains the top-level script for deploying the event map HTML.
- [`event_map.html`](./event_map.html) is that event map HTML.
- [`mobilize_america.rb`](./mobilize_america.rb) contains helpers for fetching event data from Mobilize America.
- [`events_airtable.rb`](./events_airtable.rb) contains helpers for fetching event data from Airtable.
- [`hubs_airtable.rb`](./hubs_airtable.rb) contains helpers for fetching hub data from Airtable (which we attempt to associate with events if possible).
