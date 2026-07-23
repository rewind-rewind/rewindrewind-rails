# RewindRewind Rails SDK

Rails integration for [RewindRewind](https://rewindrewind.com), which provides
exception and product event tracking. This gem depends on the
framework-independent [`rewind_rewind`](https://github.com/rewind-rewind/rewindrewind-ruby)
core SDK and connects it to Rails automatically.

Use the core gem directly for Sinatra, Roda, or another Rack application.

## Requirements

- Ruby 3.0 or newer
- Rails 6.1 or newer

Reporting requires a Rails version that provides `Rails.error.subscribe`, which
is the integration point for both handled and unhandled errors.

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

The Railtie subscribes to `Rails.error`, which is Rails' single reporting path.
That one subscriber covers everything: unhandled request exceptions (routed
there by `ActionDispatch::Executor`), plus handled errors from controllers,
jobs, `Rails.error.report`, and `Rails.error.handle`. It preserves handled,
severity, source, context, and identity metadata. Legacy `user_id` context is
accepted as a fallback.

### Why no Rack middleware on Rails

`RewindRewind::Rack` is for bare Rack hosts — Sinatra, Roda, Hanami — that have
no error reporter of their own. As of 1.3.0 the Railtie no longer inserts it,
because on Rails it was both redundant and harmful.

Rails already distinguishes bugs from ordinary HTTP outcomes:
`ActionDispatch::ExceptionWrapper.rescue_responses` maps the latter to status
symbols, `ActionDispatch::ShowExceptions` records the verdict on the request as
`action_dispatch.report_exception`, and `ActionDispatch::Executor` reports to
`Rails.error` only when that verdict says to.

`config.middleware.use` *appends*, so the middleware landed innermost — inside
`ShowExceptions`. It therefore saw and reported every exception before Rails had
classified any of them, which meant routine 4xx traffic arrived as errors:
`ActionController::BadRequest` from a malformed multipart body (a common
scanner probe), `RoutingError`, `RecordNotFound`, and the rest of the
`rescue_responses` table.

Deferring to Rails also means anything a host app registers itself is honoured
automatically, with no denylist to maintain:

```ruby
config.action_dispatch.rescue_responses["MyApp::NotAuthorized"] = :forbidden
```

One caveat, in development only: `ActionDispatch::Reloader` subclasses
`Executor` and is inserted inside `ShowExceptions` when reloading is enabled.
Its inherited `rescue Exception` reports unconditionally, so rescuable 4xx are
still reported in development. Production, where reloading is off, is
unaffected.

### Deduplication and exclusions

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
