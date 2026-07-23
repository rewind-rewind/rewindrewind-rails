# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require "rack/mock"
require "rails"
require "action_controller/railtie"

require "rewind_rewind-rails"

# Configure before boot so the Railtie's `unless RewindRewind.configured?`
# branch behaves the way a real host app's initializer makes it behave.
# Transport stays off: every assertion here stubs `capture_exception`, and
# `enabled = false` guarantees nothing leaves the machine even if one slips.
RewindRewind.configure do |c|
  c.api_key     = "rrpub_test"
  c.environment = "test"
  c.enabled     = false
  c.logger      = Logger.new(IO::NULL)
end

# A minimal but genuinely-booted Rails application. The middleware stack, the
# ShowExceptions/Executor pairing and the Rails.error reporter are all real —
# that is the whole point, since the behaviour under test lives in how those
# three interact with the Railtie.
class RewindTestApp < ::Rails::Application
  config.root = File.expand_path("..", __dir__)
  config.eager_load = false
  config.logger = Logger.new(IO::NULL)

  # Model production, not development. This matters: ActionDispatch::Reloader
  # subclasses ActionDispatch::Executor and is inserted *inside*
  # ShowExceptions, but only `if config.reloading_enabled?`. Its inherited
  # `rescue Exception` reports unconditionally, without consulting
  # `rescue_response?` — so with reloading on, Rails itself reports rescuable
  # 4xx. Production has reloading off, where the outermost Executor honours the
  # `action_dispatch.report_exception` verdict correctly.
  config.enable_reloading = false
  config.secret_key_base = "a" * 64
  config.hosts.clear

  # Mirror production: render exceptions rather than re-raising, so
  # ShowExceptions performs its `rescue_response?` classification.
  config.action_dispatch.show_exceptions = :all
  config.consider_all_requests_local = false

  # Avoid depending on public/*.html fixtures for the rendered error pages.
  config.exceptions_app = lambda do |env|
    [ env["PATH_INFO"].delete("/").to_i, { "Content-Type" => "text/plain" }, [ "error" ] ]
  end
end

RewindTestApp.initialize!

# A real controller, because the production failure happens *inside* controller
# dispatch: ActionController::Instrumentation#process_action builds
# `filtered_parameters` for the log line, which forces the request body to be
# parsed, which is where a malformed multipart body raises. A bare Rack lambda
# never touches params and so would not reproduce it.
class SessionsController < ActionController::Base
  def create
    head :ok
  end
end

Rails.application.routes.draw do
  root to: ->(_env) { [ 200, { "Content-Type" => "text/plain" }, [ "ok" ] ] }
  post "/", to: SessionsController.action(:create)
  get "/boom", to: ->(_env) { raise RuntimeError, "genuinely unhandled" }
end

module RewindTestHelpers
  # A Rack input that presents an empty body, reproducing the
  # `Rack::Multipart::EmptyContentError` a scanner triggers by POSTing a
  # multipart content-type with no content.
  class EmptyRackInput
    def read(*) = ""
    def rewind = nil
    def gets = nil
    def each = nil
    def set_encoding(*) = self
  end

  # Records everything the SDK would have transmitted during the block.
  def capturing_exceptions
    captured = []
    RewindRewind.stub(:capture_exception, ->(error, **) { captured << error }) do
      yield
    end
    captured
  end

  def middleware_classes
    Rails.application.middleware.map(&:klass)
  end
end
