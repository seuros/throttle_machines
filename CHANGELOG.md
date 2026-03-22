# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.3](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.1.2...throttle_machines/v0.1.3) (2026-03-22)


### Features

* add matryoshka pattern with Rust native extension ([97d41a6](https://github.com/seuros/throttle_machines/commit/97d41a6ddf71e042f437c44315c40e3d30c9efe1))
* add matryoshka pattern with Rust native extension ([3f614cb](https://github.com/seuros/throttle_machines/commit/3f614cbefe8b489f6627b35b635ed954e9e84d4d))


### Bug Fixes

* bump breaker_machines to ~&gt; 0.10 and upgrade magnus to 0.8.2 ([62b1c20](https://github.com/seuros/throttle_machines/commit/62b1c2007879775eed1d8412caba641c7ef345bd))
* lower Ruby requirement to 3.3.0 for TruffleRuby compatibility ([2067cc7](https://github.com/seuros/throttle_machines/commit/2067cc775362cb268d2e601aeb8c396449ca1be2))
* upgrade magnus to 0.8.2 and refresh lock file ([01c6924](https://github.com/seuros/throttle_machines/commit/01c692477c05bd927501b595a4cfb162de968087))

## [0.1.2](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.1.1...throttle_machines/v0.1.2) (2025-11-11)


### Features

* Add Rails 8.1 support and remove ActiveSupport::Configurable deprecation ([#4](https://github.com/seuros/throttle_machines/issues/4)) ([684fe6f](https://github.com/seuros/throttle_machines/commit/684fe6fc0b5a0dd150cc4b08d872c37f46bffdff))

## [0.1.1](https://github.com/seuros/throttle_machines/compare/throttle_machines-v0.1.0...throttle_machines/v0.1.1) (2025-08-08)


### Bug Fixes

* extract lua code ([d4821aa](https://github.com/seuros/throttle_machines/commit/d4821aaa411919ef63a6fdc681e977e9b4eec8e4))
* extract lua code ([aa87d14](https://github.com/seuros/throttle_machines/commit/aa87d146911b760cfef1b76f6d2dd87ad6870458))
* versioning ([df0a3f8](https://github.com/seuros/throttle_machines/commit/df0a3f89ba027639f99fa6a49cdc10b9ba9dcdea))

## [Unreleased]

### Added
- Initial implementation of ThrottleMachines
- Core rate limiting engine with temporal precision
- Support for multiple storage backends
- Elegant API design for Rails integration
