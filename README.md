# rewind_rewind-rails

Rails integration for [RewindRewind](https://rewindrewind.com) — exception and
event tracking. This gem depends on the framework-agnostic
[`rewind_rewind`](https://github.com/rewind-rewind/rewindrewind-ruby) core and
auto-wires it into Rails.

> Not on Rails? Use the core [`rewind_rewind`](https://github.com/rewind-rewind/rewindrewind-ruby)
> gem directly — it ships a pure Rack middleware that works with Sinatra, Roda,
> or any Rack app.

## Install

Install from the RewindRewind gem index (no public RubyGems account needed):

```ruby
# Gemfile
source "https://rewindrewind.com/gems" do
  gem "rewind_rewind-rails"
end
```

```sh
bundle install
```

## Configure

The Railtie handles all the plumbing automatically — it inserts the Rack
middleware (unhandled request exceptions) and subscribes to `Rails.error`
(handled errors, jobs, `Rails.error.handle`). You only supply credentials:

```ruby
# config/initializers/rewind_rewind.rb
RewindRewind.configure do |c|
  c.api_key     = ENV["REWINDREWIND_PUBLIC_KEY"] # rrpub_… project key
  c.environment = Rails.env
  c.release     = ENV["GIT_SHA"]
  c.enabled     = Rails.env.production?
  c.tags        = { service: "my-app" }
end
```

That's it. Unhandled and handled exceptions now flow to RewindRewind with
correct in-app stack-frame detection. The environment defaults to `Rails.env`,
`project_root` to `Rails.root`, and the logger to `Rails.logger` when not set.

## What it wires

- **Rack middleware** (`RewindRewind::Rack`, from the core gem) — reports
  unhandled exceptions raised during request handling.
- **`Rails.error` subscriber** — forwards handled errors reported via
  `Rails.error.report` / `Rails.error.handle`, carrying their
  handled/severity/source metadata.
