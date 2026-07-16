# RewindRewind Rails SDK

Rails integration for [RewindRewind](https://rewindrewind.com), which provides
exception and product event tracking. This gem depends on the
framework-independent [`rewind_rewind`](https://github.com/rewind-rewind/rewindrewind-ruby)
core SDK and connects it to Rails automatically.

Use the core gem directly for Sinatra, Roda, or another Rack application.

## Requirements

- Ruby 3.0 or newer
- Rails 6.1 or newer

The Rack middleware works across supported Rails versions. Handled-error
reporting also requires a Rails version that provides `Rails.error.subscribe`.

## Installation

Install the gem from the RewindRewind gem index:

```ruby
# Gemfile
source "https://rewindrewind.com/gems" do
  gem "rewind_rewind-rails"
end
```

Then run:

```sh
bundle install
```

## Configuration

Set a public project key. RewindRewind project keys start with `rrpub_` and are
safe to use in application code.

```sh
REWINDREWIND_PROJECT_KEY=rrpub_xxx
```

The SDK reads `REWINDREWIND_PROJECT_KEY`, uses `Rails.env` as the environment,
and defaults the project root and logger to their Rails equivalents when the
Railtie creates the configuration.

Use an initializer when you need explicit settings:

```ruby
# config/initializers/rewind_rewind.rb
RewindRewind.configure do |config|
  config.api_key     = ENV.fetch("REWINDREWIND_PROJECT_KEY")
  config.environment = Rails.env
  config.release     = ENV["REWINDREWIND_RELEASE"]
  config.enabled     = Rails.env.production?
  config.tags        = { service: "my-app" }
  config.project_root = Rails.root
  config.logger      = Rails.logger
end
```

See the [Ruby SDK README](https://github.com/rewind-rewind/rewindrewind-ruby)
for capture methods and all core configuration options.

## Automatic reporting

The Railtie adds two integrations:

- `RewindRewind::Rack` reports exceptions raised during request handling, adds
  safe request context, and re-raises each exception.
- A `Rails.error` subscriber reports handled errors from controllers, jobs,
  `Rails.error.report`, and `Rails.error.handle`. It preserves handled,
  severity, source, context, and identity metadata. Legacy `user_id` context is
  accepted as a fallback.

The integrations mark each exception object after reporting it so the same
error is not sent twice. The core SDK captures all exception classes by default.
Configure `excluded_exceptions` when specific framework exceptions are known to
be non-actionable for your application.

For a starting point, opt into the core SDK's suggested framework list:

```ruby
config.excluded_exceptions =
  RewindRewind::Configuration::SUGGESTED_EXCLUDED_EXCEPTIONS
```

## Development

```sh
bin/test
```

## License

MIT
