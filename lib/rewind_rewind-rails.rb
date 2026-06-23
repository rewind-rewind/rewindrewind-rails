# frozen_string_literal: true

# Entry point for the rewind_rewind-rails gem. Requiring this (which Rails does
# automatically for every gem in the Gemfile) loads the core SDK and registers
# the Railtie, which auto-inserts the Rack middleware and subscribes to
# Rails.error. Rails apps need no manual wiring beyond an optional
# RewindRewind.configure block for the api_key/tags/release.
require "rewind_rewind"
require "rewind_rewind/rails/railtie"
