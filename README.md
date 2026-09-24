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

The Railtie adds two integrations, plus the browser helper described below:

- `RewindRewind::Rack` reports exceptions raised during request handling, adds
  safe request context (method, path, url, ip, user agent), and re-raises each
  exception so your own error handling is untouched.
- A `Rails.error` subscriber reports handled errors from controllers, jobs,
  `Rails.error.report`, and `Rails.error.handle`. It preserves handled,
  severity, source, context, and identity metadata. Legacy `user_id` context is
  accepted as a fallback.

Both send through the core SDK's background worker, so a failed request is not
held open while its exception is reported. See
[Delivery](https://github.com/rewind-rewind/rewindrewind-ruby#delivery) for the
worker settings and for `sync: true`.

### Loud by default

The middleware is innermost (`config.middleware.use` appends), so it sees
exceptions before `ActionDispatch::ShowExceptions` classifies them against
`ActionDispatch::ExceptionWrapper.rescue_responses`. That is deliberate.

`rescue_responses` answers *"what HTTP status should this become?"* — a
different question from *"is this worth a developer's attention?"* The two come
apart constantly:

| Exception | Status | Worth reporting? |
| --- | --- | --- |
| `ActiveRecord::RecordInvalid` from a failed `save!` | 422 | Usually yes — a bug |
| `ActiveRecord::RecordNotFound` in internal lookup code | 404 | Usually yes |
| `ActionController::BadRequest` from empty multipart | 400 | Usually no — a scanner |
| `ActionController::RoutingError` | 404 | Usually no |

Only the host application can tell those apart, so the SDK reports everything
and lets you decide what to drop. Rails' own reporting path, by contrast, skips
every entry in `rescue_responses` — which is why deferring to it silently loses
the first two rows.

### Excluding what you don't want

Suppression is a denylist on the core configuration. Matching is by
fully-qualified class name and walks both the ancestry and the `cause` chain, so
listing a wrapped framework error catches the wrapper too:

```ruby
RewindRewind.configure do |c|
  c.excluded_exceptions =
    RewindRewind::Configuration::SUGGESTED_EXCLUDED_EXCEPTIONS
end
```

`SUGGESTED_EXCLUDED_EXCEPTIONS` is a starting point covering the common
framework 4xx. It includes `ActiveRecord::RecordNotFound`; drop that entry if
you want failed lookups reported:

```ruby
c.excluded_exceptions =
  RewindRewind::Configuration::SUGGESTED_EXCLUDED_EXCEPTIONS -
  %w[ActiveRecord::RecordNotFound]
```

### Deduplication

Both integrations mark each exception object after reporting it, so the same
error is never sent twice. The middleware runs first and wins, which is what
attaches request context to unhandled request exceptions.

## Browser errors

Server-side reporting covers the request. To also report what fails in the
visitor's browser, add one line to your layout, as early in `<head>` as your
content security policy allows:

```erb
<%= rewind_rewind_browser_tag %>
```

Set the project's public key alongside the server key. It is a different
credential: it ships to every visitor, so it lives in the Rails-side namespace
rather than on the core configuration.

```sh
REWINDREWIND_PUBLIC_KEY=rrpub_xxx
```

```ruby
# config/initializers/rewind_rewind.rb — optional; the env var is enough
Rails.application.config.rewind_rewind.public_key = ENV["REWINDREWIND_PUBLIC_KEY"]
Rails.application.config.rewind_rewind.enabled    = Rails.env.production?
Rails.application.config.rewind_rewind.init_options = { sample_rate: 0.5 }
```

The helper renders nothing when there is no public key or when `enabled` is
`false`, so it is safe to leave in the layout for every environment. It picks up
the environment and release from your `RewindRewind.configure` block, so the
browser and the server always report against the same deploy.

### Why a helper and not a snippet

The hosted SDK installs in two parts: a small ES5 pre-load stub, then `init()`.
The stub is not decoration. The bundle is fetched `async`, so the stub holds the
temporary `error`, `unhandledrejection` and `window.onerror` hooks that cover
the window between page parse and the bundle landing — which is exactly where
import-map failures, boot-time syntax errors on older engines, and framework
boot errors happen.

A hand-copied stub goes stale silently. It keeps reporting steady-state errors,
so nothing looks broken, while every error in that early window is dropped.
Rendering the snippet from the gem means the stub travels with the gem version
and `bundle update` is the whole upgrade path.

### Passing init options

Any extra keyword reaches the browser SDK's `init()`. Snake_case is camelized,
and Ruby regexps become JavaScript literals:

```erb
<%= rewind_rewind_browser_tag(
      sample_rate: 0.5,
      ignore_errors: [/Object Not Found Matching Id:\d+/, "Script error."]
    ) %>
```

Regexp syntax that JavaScript cannot run — `\A`, `\z`, `\h`, lookbehind,
`//x` — raises `ArgumentError` rather than shipping a filter that silently never
matches. For anything Ruby cannot express, emit JavaScript verbatim:

```erb
<%= rewind_rewind_browser_tag(
      before_send: RewindRewind::Rails::Browser.raw(
        "function (payload) { return payload.message.length > 500 ? null : payload; }"
      )
    ) %>
```

## Development

```sh
bin/test
```

## License

MIT
