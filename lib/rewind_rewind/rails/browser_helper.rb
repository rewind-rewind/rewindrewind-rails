# frozen_string_literal: true

require_relative "browser"

module RewindRewind
  module Rails
    # View helper that renders the browser SDK install. Mixed into ActionView
    # by the Railtie, so a host layout needs one line:
    #
    #   <%= rewind_rewind_browser_tag %>
    #
    # Place it in <head>, as early as the CSP nonce allows. The stub's whole
    # purpose is to be in place before anything else can throw; a tag at the
    # bottom of <body> still works, but it cannot cover what already failed.
    #
    # Everything is resolved from `config.rewind_rewind` (see
    # {RewindRewind::Rails::Browser.settings}), so the common case takes no
    # arguments. Per-call overrides win, and any extra keyword is passed
    # through to the browser SDK's init():
    #
    #   <%= rewind_rewind_browser_tag(
    #         sample_rate: 0.5,
    #         ignore_errors: [/Object Not Found Matching Id:\d+/]
    #       ) %>
    #
    # Renders nothing when the browser SDK is disabled or has no public key,
    # which is what keeps it safe to leave in the layout for every environment.
    module BrowserHelper
      # @param options [Hash] overrides for {Browser.settings} and init().
      # @return [ActiveSupport::SafeBuffer] the <script> tag, or empty.
      def rewind_rewind_browser_tag(**options)
        settings = Browser.settings(**options)
        return ActiveSupport::SafeBuffer.new unless settings

        javascript = Browser.javascript(**settings)
        content_tag(:script, javascript.html_safe, nonce: rewind_rewind_nonce)
      end

      private

      # Rails only exposes a nonce when a content security policy is
      # configured, and reads it off the request — which a view rendered
      # outside a request does not have. Without either, the attribute must be
      # absent rather than empty.
      def rewind_rewind_nonce
        return nil unless respond_to?(:content_security_policy_nonce)
        return nil if respond_to?(:request) && request.nil?

        content_security_policy_nonce
      end
    end
  end
end
