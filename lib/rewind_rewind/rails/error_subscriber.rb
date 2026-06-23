# frozen_string_literal: true

module RewindRewind
  module Rails
    # Subscriber for the Rails error-reporting API (`Rails.error.report`).
    #
    # Registered by the Railtie so that any error surfaced through Rails'
    # unified error reporter — controllers, jobs, `Rails.error.handle`, etc. —
    # is forwarded to RewindRewind with its handled/severity/source metadata.
    #
    # This file is only ever loaded from the Railtie, which itself only loads
    # when Rails is defined, so referencing Rails here is safe.
    class ErrorSubscriber
      def report(error, handled:, severity:, context: {}, source: nil)
        # The Rack middleware and this subscriber can both see the same
        # unhandled exception. Whichever path runs first captures it; the
        # second no-ops to avoid duplicate issues.
        return if RewindRewind.already_reported?(error)

        RewindRewind.capture_exception(
          error,
          level: normalize_severity(severity),
          tags: { handled: handled, source: source }.compact,
          extra: { context: json_safe(context) }.compact,
          user: user_from(context)
        )
        RewindRewind.mark_reported!(error)
      rescue StandardError => e
        ::Rails.logger&.warn("[RewindRewind] error subscriber failed: #{e.class}: #{e.message}")
      end

      private

      def normalize_severity(severity)
        case severity
        when :warning then "warning"
        when :info then "info"
        else "error"
        end
      end

      def user_from(context)
        return nil unless context.respond_to?(:[])

        id = context[:user_id] || context["user_id"]
        id.nil? ? nil : { id: id.to_s }
      end

      def json_safe(context)
        return {} unless context.respond_to?(:to_h)

        context.to_h.each_with_object({}) do |(k, v), acc|
          acc[k.to_s] = stringify(v)
        end
      rescue StandardError
        {}
      end

      def stringify(value)
        case value
        when String, Numeric, true, false, nil then value
        when Symbol then value.to_s
        else value.to_s
        end
      end
    end
  end
end
