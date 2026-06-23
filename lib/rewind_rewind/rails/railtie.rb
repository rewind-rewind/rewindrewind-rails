# frozen_string_literal: true

require "rewind_rewind"
require_relative "version"
require_relative "error_subscriber"

module RewindRewind
  module Rails
    # Rails glue. Loaded only when Rails is present (guarded in the entrypoint).
    #
    # Responsibilities:
    #   1. Default the project_root to Rails.root and environment to Rails.env
    #      when the host hasn't configured RewindRewind explicitly.
    #   2. Insert the pure {RewindRewind::Rack} middleware so unhandled request
    #      exceptions are reported.
    #   3. Subscribe to the Rails error reporter so handled errors flow through
    #      too.
    #
    # Hosts can still call {RewindRewind.configure} in an initializer to set the
    # api_key, tags, release, etc. — the Railtie only fills in framework-derived
    # defaults and wires up the plumbing.
    class Railtie < ::Rails::Railtie
      config.rewind_rewind = ActiveSupport::OrderedOptions.new

      initializer "rewind_rewind.configure" do |app|
        # Establish Rails-aware defaults without clobbering an explicit
        # configure block the host may already have run.
        unless RewindRewind.configured?
          RewindRewind.configure do |c|
            c.environment ||= ::Rails.env.to_s
            c.project_root = [::Rails.root.to_s, c.project_root].flatten.compact.uniq
            c.logger ||= ::Rails.logger
          end
        end

        app.config.middleware.use RewindRewind::Rack
      end

      initializer "rewind_rewind.subscribe" do
        if ::Rails.respond_to?(:error) && ::Rails.error.respond_to?(:subscribe)
          ::Rails.error.subscribe(ErrorSubscriber.new)
        end
      end
    end
  end
end
