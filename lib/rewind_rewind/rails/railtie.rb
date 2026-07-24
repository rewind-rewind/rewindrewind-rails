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
    #   2. Insert {RewindRewind::Rack} so every exception raised during request
    #      handling is reported, with request context, and then re-raised.
    #   3. Subscribe to the Rails error reporter so handled errors — and errors
    #      from jobs and other non-request code — flow through too.
    #
    # On reporting policy: the middleware is innermost (`config.middleware.use`
    # appends), so it sees exceptions before ActionDispatch::ShowExceptions
    # classifies them against ExceptionWrapper.rescue_responses. That is
    # deliberate. `rescue_responses` answers "what HTTP status should this
    # become?", which is not the same question as "is this worth a developer's
    # attention?" — an ActiveRecord::RecordInvalid from a failed `save!` is a
    # 422 *and* usually a bug, while an ActionController::BadRequest from a
    # malformed multipart body is a 400 and usually a scanner. Only the host
    # can tell those apart.
    #
    # So the SDK is loud by default and suppression is the host's explicit
    # decision, via the core denylist:
    #
    #   config.excluded_exceptions =
    #     RewindRewind::Configuration::SUGGESTED_EXCLUDED_EXCEPTIONS
    #
    # Being innermost also means reports carry request context (method, path,
    # url, ip, user agent), which the Rails.error path does not supply.
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
