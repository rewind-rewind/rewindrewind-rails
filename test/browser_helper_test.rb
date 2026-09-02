# frozen_string_literal: true

require "test_helper"
require "action_view"

# The helper is the whole point of the browser half of this gem: hosts get one
# line in a layout instead of a snippet they copy once and never update again.
class BrowserHelperTest < Minitest::Test
  def setup
    @config = Rails.application.config.rewind_rewind
    @original_key = @config[:public_key]
    @original_enabled = @config[:enabled]
    @config[:public_key] = "rrpub_live"
    @config[:enabled] = nil
  end

  def teardown
    @config[:public_key] = @original_key
    @config[:enabled] = @original_enabled
  end

  def test_the_railtie_mixes_the_helper_into_action_view
    assert_includes ActionView::Base.ancestors, RewindRewind::Rails::BrowserHelper
  end

  def test_renders_a_script_tag_carrying_the_stub_and_init
    html = view.rewind_rewind_browser_tag

    assert_match(/\A<script>/, html)
    assert_includes html, "_earlyErrorHandler"
    assert_includes html, '"key": "rrpub_live"'
    assert_match(%r{</script>\z}, html)
  end

  def test_the_script_body_is_not_html_escaped
    html = view.rewind_rewind_browser_tag(ignore_errors: [/a && b/])

    assert_includes html, "&&"
    refute_includes html, "&amp;&amp;"
  end

  def test_renders_nothing_when_the_browser_sdk_has_no_public_key
    @config[:public_key] = nil
    ENV.delete("REWINDREWIND_PUBLIC_KEY")

    assert_equal "", view.rewind_rewind_browser_tag
    assert_predicate view.rewind_rewind_browser_tag, :html_safe?
  end

  def test_renders_nothing_when_the_browser_sdk_is_disabled
    @config[:enabled] = false

    assert_equal "", view.rewind_rewind_browser_tag
  end

  def test_carries_the_content_security_policy_nonce_when_one_exists
    nonced = view
    nonced.define_singleton_method(:content_security_policy_nonce) { "n0nce" }
    nonced.define_singleton_method(:request) { :present }

    assert_includes nonced.rewind_rewind_browser_tag, 'nonce="n0nce"'
  end

  def test_omits_the_nonce_attribute_when_there_is_no_policy
    refute_includes view.rewind_rewind_browser_tag, "nonce"
  end

  def test_per_call_options_reach_the_init_call
    html = view.rewind_rewind_browser_tag(sample_rate: 0.25, release: "deadbeef")

    assert_includes html, '"sampleRate": 0.25'
    assert_includes html, '"release": "deadbeef"'
  end

  private

  def view
    ActionView::Base.empty
  end
end
