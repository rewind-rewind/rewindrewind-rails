# frozen_string_literal: true

require_relative "lib/rewind_rewind/rails/version"

Gem::Specification.new do |spec|
  spec.name        = "rewind_rewind-rails"
  spec.version     = RewindRewind::Rails::VERSION
  spec.summary     = "Rails integration for the RewindRewind Ruby SDK"
  spec.description = "Auto-wires RewindRewind into Rails: inserts the Rack " \
                     "middleware for unhandled request exceptions and subscribes " \
                     "to Rails.error for handled errors. Depends on rewind_rewind."
  spec.authors  = ["RewindRewind"]
  spec.email    = ["sdk@rewindrewind.com"]
  spec.homepage = "https://rewindrewind.com"
  spec.license  = "MIT"

  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir["lib/**/*.rb"] + ["README.md"]
  spec.require_paths = ["lib"]

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rewind-rewind/rewindrewind-rails"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Depends on the framework-agnostic core. Railties (>= 6.1) is provided by the
  # host Rails app; the Railtie only references ::Rails::Railtie at load time.
  spec.add_dependency "rewind_rewind", "~> 1.1"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
