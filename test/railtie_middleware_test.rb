# frozen_string_literal: true

require "test_helper"

# The integration is deliberately LOUD: RewindRewind::Rack wraps the app and
# reports every exception raised during request handling, then re-raises so the
# host's own error handling is untouched. Suppression is the host's decision,
# expressed as a denylist via `config.excluded_exceptions` — not something the
# SDK infers from Rails' `rescue_responses` table.
#
# That table answers "what HTTP status should this become?", which is a
# different question from "is this worth a developer's attention?". An
# ActiveRecord::RecordInvalid from a failed `save!` is a 422 *and* usually a
# bug; ActionController::BadRequest from a malformed multipart body is a 400
# and usually a scanner. Only the host can tell those apart, so the host
# decides.
#
# Being innermost also means the report carries request context (method, path,
# url, ip, user agent) that the Rails.error path alone does not provide.
class RailtieMiddlewareTest < Minitest::Test
  include RewindTestHelpers

  def test_rack_middleware_is_inserted_on_rails
    assert_includes middleware_classes, RewindRewind::Rack,
                    "The Rack middleware is what makes request-exception " \
                    "reporting loud and request-context-aware."
  end

  def test_rails_exception_handling_pair_is_intact
    assert_includes middleware_classes, ActionDispatch::ShowExceptions
    assert_includes middleware_classes, ActionDispatch::Executor
  end

  # Rails classifies ActionController::BadRequest as a rescuable 400 and does
  # not report it. We do report it, because "renders as a 4xx" is not the same
  # as "not worth knowing about". Hosts that disagree exclude it by name.
  def test_rescuable_request_exception_is_reported_by_default
    calls = capturing_calls do
      response = Rack::MockRequest.new(Rails.application).post(
        "/",
        "CONTENT_TYPE" => "multipart/form-data; boundary=----rewind-test",
        input: EmptyRackInput.new
      )

      assert_equal 400, response.status, "Rails' own status handling must be untouched"
    end

    assert_equal 1, calls.size
    assert_equal "ActionController::BadRequest", calls.first[:error].class.name
  end

  # The reason the middleware earns its place: Rails.error alone hands the
  # subscriber a context of {controller: ...} with no request details.
  def test_reported_request_exception_carries_request_context
    calls = capturing_calls do
      Rack::MockRequest.new(Rails.application).get(
        "/boom",
        "HTTP_USER_AGENT" => "curl/8.0",
        "REMOTE_ADDR" => "203.0.113.9"
      )
    end

    request = calls.first[:request]

    refute_nil request, "request context must accompany request exceptions"
    assert_equal "GET", request[:method]
    assert_equal "/boom", request[:path]
    assert_equal "curl/8.0", request[:user_agent]
    assert_equal "203.0.113.9", request[:remote_ip]
  end

  # Both the middleware and the Rails.error subscriber can see the same
  # unhandled exception. The already_reported? marker must keep that to one
  # issue rather than two.
  def test_unhandled_request_exception_is_reported_exactly_once
    captured = capturing_exceptions do
      response = Rack::MockRequest.new(Rails.application).get("/boom")

      assert_equal 500, response.status
    end

    assert_equal 1, captured.size, "the Rack and Rails.error paths must not double-report"
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
