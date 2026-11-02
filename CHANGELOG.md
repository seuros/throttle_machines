# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.2](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.4.1...throttle_machines/v0.4.2) (2026-11-01)


### Bug Fixes

* give the GC time instead of assuming it ran ([2ab097f](https://github.com/seuros/throttle_machines/commit/2ab097f4f5160da18d760cd0ba6a807071cd866e))

## [0.4.1](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.4.0...throttle_machines/v0.4.1) (2026-11-01)


### Features

* gems:push_all fetches the release itself ([0d161ce](https://github.com/seuros/throttle_machines/commit/0d161cedd7983e6ac10b787d072ee9a82b858333))
* pass a rubygems OTP through GEM_OTP ([6ee50b0](https://github.com/seuros/throttle_machines/commit/6ee50b07703bd123fb902780a2aeae30601c74a5))
* verify release gem checksums before pushing ([409258c](https://github.com/seuros/throttle_machines/commit/409258cedd8844272eb4fb16f301b141b4c087c7))


### Bug Fixes

* enable the rb-sys compiled fallback so new Rubies can build ([9f1f1b6](https://github.com/seuros/throttle_machines/commit/9f1f1b6289d697ff2f3894820e7826a9ddbd1244))
* raise the breaker_machines floor to 0.24.0 ([897ff41](https://github.com/seuros/throttle_machines/commit/897ff41e49b0b15fc96b067ceb38ab5f254a514d))
* raise the chrono_machines floor to 0.12.1 ([e6bfcbe](https://github.com/seuros/throttle_machines/commit/e6bfcbebf222e0b553ef445e4b8bf80de7d7be74))

## [0.4.0](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.3.4...throttle_machines/v0.4.0) (2026-11-01)


### ⚠ BREAKING CHANGES

* a Storage::Base subclass implementing gcra or token_bucket must also implement reset_gcra and reset_token_bucket, or supports? reports the algorithm unavailable.

### Features

* bound the throttle wait by the caller's deadline ([37a7784](https://github.com/seuros/throttle_machines/commit/37a7784ca6b5eed976d5b61ca4b6d0a51502a407))


### Bug Fixes

* a failed gem push fails the release ([6c51c25](https://github.com/seuros/throttle_machines/commit/6c51c25a5f2a424c8d165df9fa04d69960808ef3))
* a lone checkout can bundle ([5cc6824](https://github.com/seuros/throttle_machines/commit/5cc68244e7f7f3ce3a3dfc665a7e6c907648d667))
* a reset deletes its own limiter's keys, not a pattern ([b9f93af](https://github.com/seuros/throttle_machines/commit/b9f93af050b3790f881dd7fe15882ec7f6a53f4a))
* a spent budget raised nothing and ran unbounded ([d58240e](https://github.com/seuros/throttle_machines/commit/d58240ebb675e7ec55b4eac0886d223807eabc51))
* backoff: selected jitter, never the backoff strategy ([f2f6a2d](https://github.com/seuros/throttle_machines/commit/f2f6a2dcdf776839bc6c1fbbeed18a4384e2fc4a))
* both backends report a wait as a Float ([525c9a6](https://github.com/seuros/throttle_machines/commit/525c9a6e3791fbe3e93b5c35ac09f77d470c65a5))
* bound the storage timeout by the caller's budget ([1bef8b1](https://github.com/seuros/throttle_machines/commit/1bef8b1d191a421a0f0bdcb9d4d818851e1360b8))
* break_circuit shares one circuit, limiters reject a zero rate ([acf5bd8](https://github.com/seuros/throttle_machines/commit/acf5bd8d46b2a655af9b970889e8e47fb5bbf188))
* **storage:** let a memory store be garbage collected ([e173f89](https://github.com/seuros/throttle_machines/commit/e173f89bf056dbf75a0d514fd7a857bdeddcc50a))

## [0.3.4](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.3.3...throttle_machines/v0.3.4) (2026-10-30)


### Features

* **storage:** add ActiveSupport::Cache storage ([176c366](https://github.com/seuros/throttle_machines/commit/176c366dc159ff4493482913ddc4110462590344))


### Bug Fixes

* **deps:** require breaker_machines 0.22.1 ([8bbcdda](https://github.com/seuros/throttle_machines/commit/8bbcddaf6459d6905e47401af6b5de73001f6537))
* **storage:** reject algorithms a storage cannot run when the limiter is built ([a024d23](https://github.com/seuros/throttle_machines/commit/a024d23ab9b24fb93d4f9fa5aa16bf7b56bee253))

## [0.3.3](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.3.2...throttle_machines/v0.3.3) (2026-10-27)


### Bug Fixes

* Zeitwerk ignores native_speedup.rb, so apps that eager load (production, CI) boot instead of raising NameError for ThrottleMachines::NativeSpeedup ([#20](https://github.com/seuros/throttle_machines/issues/20)) ([a333434](https://github.com/seuros/throttle_machines/commit/a3334348b9f328d60767bccf317842fde1c27b6e))

## [0.3.2](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.3.1...throttle_machines/v0.3.2) (2026-10-20)


### Bug Fixes

* cap in-memory storage across Ruby and native backends ([284387a](https://github.com/seuros/throttle_machines/commit/284387a091383fbbe5e9b02536084fbb7b81838d))
* **core:** cap keyed GCRA storage under identity sprays ([fb8030a](https://github.com/seuros/throttle_machines/commit/fb8030a73b4dfe03497fd7550f8ee391cca41538))

## [0.3.1](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.3.0...throttle_machines/v0.3.1) (2026-10-14)


### Features

* **core:** add KeyedGcra per-key store and GcraParams::from_rate ([b7fa7a5](https://github.com/seuros/throttle_machines/commit/b7fa7a59bcc3dfb276e4fb9be3a95e38c08fe84c))


### Bug Fixes

* admit on-schedule GCRA requests in Ruby and Redis storage ([110b5e3](https://github.com/seuros/throttle_machines/commit/110b5e3d6103180a324e7edeca585958970208f0))
* **core:** admit a token due now despite float rounding ([c46bd54](https://github.com/seuros/throttle_machines/commit/c46bd54e2d913ecc25c3a9fe8098a8116c1747d6))
* **core:** admit on-schedule GCRA requests despite float rounding ([5aa090e](https://github.com/seuros/throttle_machines/commit/5aa090e1562325e5d9474f3ec35cf1d22d5ccafb))
* token bucket rounding and truncated Redis replies ([eae0a9e](https://github.com/seuros/throttle_machines/commit/eae0a9e4a5a42b4f6fc2cc61810471d596df08b5))

## [0.3.0](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.2.4...throttle_machines/v0.3.0) (2026-10-12)


### ⚠ BREAKING CHANGES

* Rails 8.0 is no longer supported; activesupport >= 8.1 is required.

### Bug Fixes

* retain loaded Redis script SHAs ([#16](https://github.com/seuros/throttle_machines/issues/16)) ([75f2ef1](https://github.com/seuros/throttle_machines/commit/75f2ef1a48f8c5e20fec6a96bb61105b96e23d4f))
* run Redis scripts by SHA with a single EVAL fallback ([6e586e6](https://github.com/seuros/throttle_machines/commit/6e586e6d32782eb95a6b136763b870f36f8da309))


### Build System

* require Rails 8.1 and run tests with padded_cell ([f131d15](https://github.com/seuros/throttle_machines/commit/f131d15e0445db0758b8cdb96fb3a23573eafa7f))

## [0.2.4](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.2.3...throttle_machines/v0.2.4) (2026-10-10)


### Bug Fixes

* **ci:** attach release gems with gh release upload ([dd3ece4](https://github.com/seuros/throttle_machines/commit/dd3ece4a402e8b088b25648c6c786cce03832593))
* **ci:** use upload-artifact@v7; v8 does not exist ([e535e25](https://github.com/seuros/throttle_machines/commit/e535e255424179a13b7639db82cc691afdf9faf1))
* **deps:** pin breaker_machines ~&gt; 0.19 ([7621b67](https://github.com/seuros/throttle_machines/commit/7621b6718d9a93696a748464255e3f44d9a50738))


### Performance Improvements

* **ffi:** build Decision/Outcome without a kwargs hash; adopt clippy pedantic and nursery ([23c263d](https://github.com/seuros/throttle_machines/commit/23c263da35829a9375397abaae807659ca96a1ac))

## [0.2.3](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.2.2...throttle_machines/v0.2.3) (2026-10-06)


### Features

* require Ruby 4.0, magnus 0.9, Ractor-safe ext with Data results ([448ecd6](https://github.com/seuros/throttle_machines/commit/448ecd6674c5be744cc92b44d368a46552d48161))


### Bug Fixes

* **build:** skip host compile when packaging a cross gem ([2becc31](https://github.com/seuros/throttle_machines/commit/2becc317c51e2f047ee3053a0a179db78c93225e))
* **ci:** build Rust crates against Ruby 4.0 ([3a69957](https://github.com/seuros/throttle_machines/commit/3a699577ec16ef6655bf6e382012b91bd22a914a))
* **deps:** pin breaker_machines ~&gt; 0.18, chrono_machines ~&gt; 0.9 ([17e1d60](https://github.com/seuros/throttle_machines/commit/17e1d60a4b19cdf5622093accf2290615f2aaed7))

## [0.2.2](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.2.1...throttle_machines/v0.2.2) (2026-06-24)


### Features

* add native circuit breaker on shared Gate contract ([dee0b57](https://github.com/seuros/throttle_machines/commit/dee0b57b20c7c887c2e7f7e7d7d2e6a5696be118))

## [0.2.1](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.2.0...throttle_machines/v0.2.1) (2026-06-24)


### Bug Fixes

* add storage-backed async throttling ([09c8125](https://github.com/seuros/throttle_machines/commit/09c8125312dd21fb7a61c469b99faf09764cd75d))
* add storage-backed async throttling ([12fe6b5](https://github.com/seuros/throttle_machines/commit/12fe6b51631d149f849aeb818f8d6252b5f8eb04))

## [0.2.0](https://github.com/seuros/throttle_machines/compare/throttle_machines/v0.1.3...throttle_machines/v0.2.0) (2026-05-25)


### Bug Fixes

* build native extension with current rb_sys ([0960f00](https://github.com/seuros/throttle_machines/commit/0960f00ecbb3f55fd888984f7474c591fc0459ed))
* ship pure ruby fallback gem ([3a54ac3](https://github.com/seuros/throttle_machines/commit/3a54ac3dffb073ece85a10c4c35ed3c426d658f6))

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
