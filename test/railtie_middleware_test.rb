# frozen_string_literal: true

require "test_helper"

# Rails already decides which exceptions are bugs and which are ordinary HTTP
# statuses: `ActionDispatch::ExceptionWrapper.rescue_responses` maps the latter
# to status symbols, `ShowExceptions` records the verdict on the request as
# `action_dispatch.report_exception`, and `ActionDispatch::Executor` reports to
# `Rails.error` only when that verdict says so.
#
# Inserting a rescue-everything Rack middleware *inside* that pair (which
# `config.middleware.use` does — it appends, so the middleware ends up
# innermost) sees every exception before Rails has classified it, and therefore
# reports things Rails deliberately would not. On Rails the middleware is also
# redundant: the Railtie already subscribes an ErrorSubscriber to Rails.error.
#
# These tests pin that contract down.
class RailtieMiddlewareTest < Minitest::Test
  include RewindTestHelpers

  def test_rack_middleware_is_not_inserted_on_rails
    refute_includes middleware_classes, RewindRewind::Rack,
                    "RewindRewind::Rack must not be in a Rails middleware stack: " \
                    "Rails.error is the reporting path, and the middleware would " \
                    "bypass ShowExceptions' rescue_response? classification."
  end

  def test_rails_exception_handling_pair_is_intact
    assert_includes middleware_classes, ActionDispatch::ShowExceptions
    assert_includes middleware_classes, ActionDispatch::Executor
  end

  # The regression this whole change exists for: an empty multipart POST is a
  # Rails-rescuable 400, not a bug.
  def test_empty_multipart_post_renders_400_without_capture
    captured = capturing_exceptions do
      response = Rack::MockRequest.new(Rails.application).post(
        "/",
        "CONTENT_TYPE" => "multipart/form-data; boundary=----rewind-test",
        input: EmptyRackInput.new
      )

      assert_equal 400, response.status
    end

    assert_empty captured,
                 "Rails classifies ActionController::BadRequest as :bad_request, " \
                 "so it must never be reported as an error."
  end

  # Guards the risk side of removing the middleware: genuinely unhandled
  # request exceptions must still be reported, end to end through the real
  # stack rather than via a direct Rails.error.report call.
  def test_unhandled_request_exception_is_still_captured
    captured = capturing_exceptions do
      response = Rack::MockRequest.new(Rails.application).get("/boom")

      assert_equal 500, response.status
    end

    assert_equal 1, captured.size,
                 "Removing the Rack middleware must not lose coverage of real errors."
    assert_instance_of RuntimeError, captured.first
    assert_equal "genuinely unhandled", captured.first.message
  end

  def test_handled_errors_reported_through_rails_error_still_reach_rewind
    error = RuntimeError.new("reportable")

    captured = capturing_exceptions do
      Rails.error.report(error, handled: false, source: "test")
    end

    assert_equal [ error ], captured
  end
end
