# frozen_string_literal: true

require "json"

module RewindRewind
  module Rails
    # Builds the browser-side install snippet.
    #
    # The hosted SDK installs in two parts: an ES5 pre-load stub, then an
    # `init()` call. The stub is not decoration. It queues API calls made
    # before the async bundle lands, and — since the bundle is fetched
    # `async` from another origin — it also owns the temporary `error`,
    # `unhandledrejection` and `window.onerror` hooks that cover that gap.
    #
    # Hosts used to hand-copy that stub out of the dashboard, which is how an
    # install silently falls behind. A stub that predates the temporary hooks
    # still looks correct and still reports steady-state errors, so nothing
    # looks broken — but every error thrown between page parse and the bundle
    # landing is dropped. That window is where import-map failures, boot-time
    # syntax errors on older engines and framework boot errors live.
    #
    # Rendering the snippet from the gem removes the failure mode: the stub
    # travels with the gem version, so `bundle update` is the whole upgrade
    # path, and the browser install can never drift from the server one.
    module Browser
      DEFAULT_ORIGIN = "https://rewindrewind.com"

      # Every public method of the bundle, shimmed so a call made before the
      # bundle lands queues instead of throwing "init is not a function".
      QUEUED_METHODS = %w[
        init captureException captureEvent captureMessage
        addBreadcrumb setIdentity setTags setContext flush
      ].freeze

      # Ruby regexp syntax with no JavaScript equivalent, plus lookbehind,
      # which the older WebKit engines this snippet exists to reach cannot
      # parse. A pattern carrying one of these compiles happily in Ruby and
      # then either throws at script parse time — taking the whole install
      # down with it — or silently never matches, quietly disabling the very
      # filter it was written for. Neither failure is visible from Ruby, so
      # refuse the pattern instead. Use {raw} to opt out.
      UNPORTABLE_REGEXP = {
        '\A'      => 'use "^"',
        '\z'      => 'use "$"',
        '\Z'      => 'use "$"',
        '\h'      => 'use "[0-9a-fA-F]"',
        '\H'      => 'use "[^0-9a-fA-F]"',
        '\R'      => 'use "(?:\r\n|[\n\r])"',
        '\X'      => "no JavaScript equivalent",
        '\G'      => "no JavaScript equivalent",
        "(?<="    => "lookbehind is unsupported before Safari 16.4",
        "(?<!"    => "lookbehind is unsupported before Safari 16.4",
        "(?#"     => "JavaScript has no inline comment group"
      }.freeze

      # A literal fragment of JavaScript, emitted verbatim. The escape hatch
      # for init options Ruby cannot express — a `beforeSend` function, or a
      # regexp this module refuses to translate.
      class RawJavaScript
        attr_reader :source

        def initialize(source)
          @source = source.to_s
        end
      end

      # @param source [String] JavaScript emitted into the snippet unchanged.
      # @return [RawJavaScript]
      def self.raw(source)
        RawJavaScript.new(source)
      end

      # The canonical pre-load stub, byte-for-byte the shape the dashboard's
      # Setup panel emits. Order-independent and safe to re-execute: inline
      # <script> tags re-run on Hotwire-Turbo body swaps, so every assignment
      # is guarded and the temporary hooks are installed exactly once.
      #
      # @param origin [String] scheme and host serving /sdk/v1/rewind.js.
      # @return [String]
      def self.preload_stub(origin: DEFAULT_ORIGIN)
        src = "#{origin.to_s.sub(%r{/+\z}, "")}/sdk/v1/rewind.js"
        <<~JS.strip
          (function (w, d) {
            var r = (w.RewindRewind = w.RewindRewind || { _q: [] });
            #{JSON.generate(QUEUED_METHODS)}
              .forEach(function (m) { r[m] = r[m] || function () { (r._q = r._q || []).push([m, arguments]); }; });
            r._earlyErrorHandler = r._earlyErrorHandler || function (e) {
              r.captureException(e.error || e.message, { filename: e.filename, line: e.lineno, column: e.colno });
            };
            r._earlyRejectionHandler = r._earlyRejectionHandler || function (e) {
              if (e.reason instanceof Error || (typeof e.reason === "string" && e.reason.length))
                r.captureException(e.reason, { source: "unhandledrejection" });
            };
            r._earlyOnError = r._earlyOnError || function (msg, src, ln, col, err) {
              r.captureException(err || msg, { filename: src, line: ln, column: col });
              return r._priorOnError ? r._priorOnError.apply(this, arguments) : undefined;
            };
            if (!r._loading) {
              r._loading = 1;
              w.addEventListener("error", r._earlyErrorHandler);
              w.addEventListener("unhandledrejection", r._earlyRejectionHandler);
              r._priorOnError = w.onerror;
              w.onerror = r._earlyOnError;
              var s = d.createElement("script"); s.async = 1; s.crossOrigin = "anonymous"; s.src = #{JSON.generate(src)}; d.head.appendChild(s);
            }
          })(window, document);
        JS
      end

      # @param options [Hash] init options, snake_case keys welcome.
      # @return [String] the `RewindRewind.init({...});` call.
      def self.init_call(options)
        "RewindRewind.init(#{js_object(options)});"
      end

      # The complete snippet: stub, then init.
      #
      # @param public_key [String] the project's public ingestion key.
      # @param environment [String, nil]
      # @param release [String, nil]
      # @param origin [String, nil]
      # @param init_options [Hash] anything else the browser SDK accepts.
      # @return [String]
      def self.javascript(public_key:, environment: nil, release: nil, origin: nil, **init_options)
        options = { key: public_key.to_s }
        options[:environment] = environment.to_s unless blank?(environment)
        options[:release] = release.to_s unless blank?(release)
        options.merge!(init_options)

        [preload_stub(origin: origin || DEFAULT_ORIGIN), init_call(options)].join("\n")
      end

      # Resolves what to render from explicit arguments, then the host's
      # `config.rewind_rewind`, then the environment, then the core SDK's own
      # configuration. Returns nil when the browser SDK should not be rendered
      # at all — disabled, or with no public key to authenticate with.
      #
      # @return [Hash, nil] keyword arguments for {javascript}.
      def self.settings(**overrides)
        options  = overrides.dup
        enabled  = options.key?(:enabled) ? options.delete(:enabled) : config[:enabled]
        return nil if enabled == false

        public_key = options.delete(:public_key) || config[:public_key] || ENV["REWINDREWIND_PUBLIC_KEY"]
        return nil if blank?(public_key)

        {
          public_key: public_key,
          environment: options.delete(:environment) || config[:environment] || core_config(:environment) || rails_env,
          release: options.delete(:release) || config[:release] || core_config(:release),
          origin: options.delete(:origin) || config[:origin] || core_config(:endpoint) || DEFAULT_ORIGIN
        }.merge(default_init_options.merge(options))
      end

      # @return [Hash] `config.rewind_rewind.init_options`, or an empty hash.
      def self.default_init_options
        value = config[:init_options]
        value.is_a?(Hash) ? value.to_h { |key, option| [key.to_sym, option] } : {}
      end

      # @return [Hash] the host's `config.rewind_rewind`, or an empty hash.
      def self.config
        app = defined?(::Rails) && ::Rails.respond_to?(:application) ? ::Rails.application : nil
        options = app&.config&.respond_to?(:rewind_rewind) ? app.config.rewind_rewind : nil
        options.respond_to?(:to_h) ? options.to_h : {}
      end

      def self.core_config(attribute)
        return nil unless RewindRewind.respond_to?(:configuration)

        value = RewindRewind.configuration.public_send(attribute)
        blank?(value) ? nil : value
      rescue NoMethodError
        nil
      end
      private_class_method :core_config

      def self.rails_env
        defined?(::Rails) && ::Rails.respond_to?(:env) ? ::Rails.env.to_s : nil
      end
      private_class_method :rails_env

      # Serializes a Ruby hash to a JavaScript object literal. JSON handles
      # almost everything; regexps and raw fragments are what JSON cannot
      # express and what browser SDK options (`ignoreErrors`, `denyUrls`,
      # `beforeSend`) most need.
      def self.js_object(options)
        pairs = options.map { |key, value| "#{JSON.generate(camelize(key))}: #{js_value(value)}" }
        "{ #{pairs.join(", ")} }"
      end
      private_class_method :js_object

      def self.js_value(value)
        case value
        when RawJavaScript then value.source
        when Regexp        then js_regexp(value)
        when Hash          then js_object(value)
        when Array         then "[#{value.map { |entry| js_value(entry) }.join(", ")}]"
        when Symbol        then JSON.generate(value.to_s)
        else                    JSON.generate(value)
        end
      end
      private_class_method :js_value

      def self.js_regexp(regexp)
        if (offender = UNPORTABLE_REGEXP.keys.find { |token| regexp.source.include?(token) })
          raise ArgumentError, "#{regexp.inspect} is not portable to JavaScript: " \
                               "#{offender} — #{UNPORTABLE_REGEXP.fetch(offender)}. " \
                               "Pass RewindRewind::Rails::Browser.raw(\"/.../\") to emit a literal unchanged."
        end
        if (regexp.options & Regexp::EXTENDED).positive?
          raise ArgumentError, "#{regexp.inspect} uses //x, which JavaScript has no equivalent for. " \
                               "Rewrite it without extended mode, or use " \
                               "RewindRewind::Rails::Browser.raw."
        end

        flags = +""
        flags << "i" if (regexp.options & Regexp::IGNORECASE).positive?
        # Ruby's //m makes `.` match newlines. That is JavaScript's //s, not
        # its //m, which only changes what ^ and $ anchor to.
        flags << "s" if (regexp.options & Regexp::MULTILINE).positive?

        "/#{regexp.source.gsub(%r{(?<!\\)/}, "\\/")}/#{flags}"
      end
      private_class_method :js_regexp

      def self.camelize(key)
        head, *rest = key.to_s.split("_")
        [head, *rest.map(&:capitalize)].join
      end
      private_class_method :camelize

      def self.blank?(value)
        value.nil? || value.to_s.strip.empty?
      end
      private_class_method :blank?
    end
  end
end
