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
    #   2. Subscribe to the Rails error reporter, which is the single reporting
    #      path on Rails — for both handled and unhandled errors.
    #
    # Deliberately absent: {RewindRewind::Rack}. That middleware exists for bare
    # Rack hosts (Sinatra, Hanami, Roda, ...) which have no error reporter of
    # their own. On Rails it is both redundant and harmful:
    #
    #   * Redundant, because ActionDispatch::Executor already routes every
    #     unhandled request exception to Rails.error, which we subscribe to.
    #   * Harmful, because `config.middleware.use` *appends*, placing the
    #     middleware innermost — inside ActionDispatch::ShowExceptions. It would
    #     therefore rescue and report exceptions before Rails has classified
    #     them, defeating ActionDispatch::ExceptionWrapper.rescue_responses.
    #     Ordinary HTTP outcomes that Rails deliberately does not report
    #     (ActionController::BadRequest from a malformed multipart body,
    #     RoutingError, RecordNotFound, ...) would be reported as errors.
    #
    # Hosts can still call {RewindRewind.configure} in an initializer to set the
    # api_key, tags, release, etc. — the Railtie only fills in framework-derived
    # defaults and wires up the plumbing.
    class Railtie < ::Rails::Railtie
      config.rewind_rewind = ActiveSupport::OrderedOptions.new

      initializer "rewind_rewind.configure" do
        # Establish Rails-aware defaults without clobbering an explicit
        # configure block the host may already have run.
        unless RewindRewind.configured?
          RewindRewind.configure do |c|
            c.environment ||= ::Rails.env.to_s
            c.project_root = [::Rails.root.to_s, c.project_root].flatten.compact.uniq
            c.logger ||= ::Rails.logger
          end
        end
      end

      initializer "rewind_rewind.subscribe" do
        if ::Rails.respond_to?(:error) && ::Rails.error.respond_to?(:subscribe)
          ::Rails.error.subscribe(ErrorSubscriber.new)
        end
      end
    end
  end
end
