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

## Steps to Run Locally

To develop the backend portion of this library locally, you'll need to obtain API keys and organization ids for Mobilize America, as well as an Airtable API key that has access to both the Hub Tracking and Event Map and Management bases (along with their associated ids). Copy `.env.example` to `.env` and fill in the fields with these values. You will also need to fill in the appropriate S3 information to ensure you have a place to upload the event data.

Then, after installing Ruby and then installing this library's dependencies using `bundle install`, you should be able to run `bundle exec ruby upload_data.rb`.

To develop the frontend portion of this library, you shouldn't need any credentials or need to install any of the dependencies. Instead, you can just edit `event_map.html` (which is entirely self-contained), viewing the results locally in your browser.
