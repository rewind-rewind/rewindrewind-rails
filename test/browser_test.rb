# frozen_string_literal: true

require "test_helper"

# The browser install is the half of the SDK that used to be hand-copied out of
# the dashboard, so these tests pin the two things drift attacks: that the stub
# still carries its temporary error hooks, and that Ruby-shaped init options
# arrive as JavaScript the browser actually understands.
class BrowserTest < Minitest::Test
  Browser = RewindRewind::Rails::Browser

  def setup
    @config = Rails.application.config.rewind_rewind
    @original = @config.to_h
    @original_env = ENV["REWINDREWIND_PUBLIC_KEY"]
  end

  def teardown
    # OrderedOptions is a Hash, so a wholesale replace is the honest reset:
    # keys a test added disappear instead of lingering as explicit nils.
    @config.replace(@original)
    ENV["REWINDREWIND_PUBLIC_KEY"] = @original_env
  end

  # --- the stub itself -------------------------------------------------------

  def test_stub_installs_the_temporary_error_hooks
    stub = Browser.preload_stub

    # These three cover the window between page parse and the async bundle
    # landing: dispatched error events, unhandled rejections, and the direct
    # window.onerror call frameworks make for exceptions they caught themselves.
    assert_includes stub, "_earlyErrorHandler"
    assert_includes stub, "_earlyRejectionHandler"
    assert_includes stub, "_earlyOnError"
    assert_includes stub, 'w.addEventListener("error", r._earlyErrorHandler);'
    assert_includes stub, 'w.addEventListener("unhandledrejection", r._earlyRejectionHandler);'
    assert_includes stub, "w.onerror = r._earlyOnError;"
  end

  def test_stub_hooks_are_installed_once_so_turbo_body_swaps_do_not_stack_them
    stub = Browser.preload_stub
    guarded = stub[/if \(!r\._loading\) \{(.*?)\n  \}/m, 1]

    refute_nil guarded, "the loader must stay inside the !r._loading guard"
    assert_includes guarded, "addEventListener"
    assert_includes guarded, "w.onerror = r._earlyOnError;"
    assert_includes guarded, "d.head.appendChild(s);"
  end

  def test_stub_shims_every_public_method_so_early_calls_queue
    stub = Browser.preload_stub

    RewindRewind::Rails::Browser::QUEUED_METHODS.each { |method| assert_includes stub, %("#{method}") }
    assert_includes stub, "_q"
  end

  def test_stub_points_at_the_configured_origin
    assert_includes Browser.preload_stub, '"https://rewindrewind.com/sdk/v1/rewind.js"'
    assert_includes Browser.preload_stub(origin: "https://errors.example.com/"),
                    '"https://errors.example.com/sdk/v1/rewind.js"'
  end

  def test_stub_loads_the_bundle_with_cors_so_stack_frames_survive
    assert_includes Browser.preload_stub, 's.crossOrigin = "anonymous";'
  end

  # --- init options ----------------------------------------------------------

  def test_javascript_emits_stub_then_init
    js = Browser.javascript(public_key: "rrpub_live", environment: "production", release: "abc123")

    assert_operator js.index("(function (w, d)"), :<, js.index("RewindRewind.init(")
    assert_includes js, '"key": "rrpub_live"'
    assert_includes js, '"environment": "production"'
    assert_includes js, '"release": "abc123"'
  end

  def test_blank_environment_and_release_are_omitted_rather_than_sent_as_null
    js = Browser.javascript(public_key: "rrpub_live", environment: nil, release: "")

    refute_includes js, '"release"'
    refute_includes js, '"environment"'
  end

  def test_snake_case_options_are_camelized_for_the_browser_sdk
    js = Browser.javascript(public_key: "k", sample_rate: 0.5, capture_non_error_rejections: true)

    assert_includes js, '"sampleRate": 0.5'
    assert_includes js, '"captureNonErrorRejections": true'
  end

  def test_regexps_become_javascript_literals
    js = Browser.javascript(public_key: "k", ignore_errors: [/Object Not Found Matching Id:\d+/i, "Script error."])

    assert_includes js, '"ignoreErrors": [/Object Not Found Matching Id:\d+/i, "Script error."]'
  end

  def test_ruby_multiline_becomes_javascript_dotall_not_javascript_multiline
    # //m means "dot matches newline" in Ruby; the same spelling in JavaScript
    # means something else entirely, and would silently change the match.
    assert_includes Browser.javascript(public_key: "k", ignore_errors: [/a.b/m]), "/a.b/s"
  end

  def test_forward_slashes_are_escaped_so_the_literal_does_not_terminate_early
    js = Browser.javascript(public_key: "k", deny_urls: [%r{https://cdn\.example\.com/}])

    assert_includes js, '/https:\/\/cdn\.example\.com\//'
  end

  def test_regexp_syntax_javascript_cannot_run_is_refused_rather_than_emitted
    error = assert_raises(ArgumentError) { Browser.javascript(public_key: "k", ignore_errors: [/\Aboom/]) }
    assert_match(/not portable to JavaScript/, error.message)
    assert_match(/use "\^"/, error.message)

    extended = assert_raises(ArgumentError) { Browser.javascript(public_key: "k", ignore_errors: [/ b o /x]) }
    assert_match(%r{//x}, extended.message)

    lookbehind = assert_raises(ArgumentError) { Browser.javascript(public_key: "k", ignore_errors: [/(?<=a)b/]) }
    assert_match(/Safari 16\.4/, lookbehind.message)
  end

  def test_raw_javascript_is_emitted_verbatim
    js = Browser.javascript(
      public_key: "k",
      before_send: Browser.raw("function (payload) { return payload; }")
    )

    assert_includes js, '"beforeSend": function (payload) { return payload; }'
  end

  def test_nested_options_are_serialized
    js = Browser.javascript(public_key: "k", tags: { tier: "pro", seats: 3 })

    assert_includes js, '"tags": { "tier": "pro", "seats": 3 }'
  end

  # --- settings resolution ---------------------------------------------------

  def test_settings_are_nil_without_a_public_key
    @config[:public_key] = nil
    ENV.delete("REWINDREWIND_PUBLIC_KEY")

    assert_nil Browser.settings
  end

  def test_settings_are_nil_when_the_browser_sdk_is_switched_off
    @config[:public_key] = "rrpub_live"
    @config[:enabled] = false

    assert_nil Browser.settings
    # An explicit argument still wins over the configured switch.
    refute_nil Browser.settings(enabled: true)
  end

  def test_settings_fall_back_to_the_core_configuration_for_environment
    @config[:public_key] = "rrpub_live"
    previous = RewindRewind.configuration.environment
    RewindRewind.configuration.environment = "staging"

    # The browser and the server should agree about which deploy they are
    # reporting for, so the core configuration answers before Rails.env does.
    assert_equal "staging", Browser.settings[:environment]
  ensure
    RewindRewind.configuration.environment = previous
  end

  def test_settings_fall_back_to_rails_env_when_nothing_else_says
    @config[:public_key] = "rrpub_live"
    previous = RewindRewind.configuration.environment
    RewindRewind.configuration.environment = nil

    assert_equal Rails.env.to_s, Browser.settings[:environment]
  ensure
    RewindRewind.configuration.environment = previous
  end

  def test_explicit_arguments_beat_configuration
    @config[:public_key] = "rrpub_config"
    @config[:environment] = "staging"

    settings = Browser.settings(public_key: "rrpub_call", environment: "production")

    assert_equal "rrpub_call", settings[:public_key]
    assert_equal "production", settings[:environment]
  end

  def test_configured_init_options_merge_with_per_call_options
    @config[:public_key] = "rrpub_live"
    @config[:init_options] = { sample_rate: 0.1, ignore_errors: ["Script error."] }

    settings = Browser.settings(sample_rate: 0.9)

    assert_in_delta 0.9, settings[:sample_rate]
    assert_equal ["Script error."], settings[:ignore_errors]
  end
end
