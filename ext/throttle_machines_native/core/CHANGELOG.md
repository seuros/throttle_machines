# Changelog

## [0.5.1](https://github.com/seuros/throttle_machines/compare/throttle-machines-v0.5.0...throttle-machines-v0.5.1) (2026-11-06)


### Bug Fixes

* keep test modules out of the packaged crate ([7f28c6e](https://github.com/seuros/throttle_machines/commit/7f28c6e2a72a9d4a30ec809be8f8a9c9462fa20e))

## [0.5.0](https://github.com/seuros/throttle_machines/compare/throttle-machines-v0.4.0...throttle-machines-v0.5.0) (2026-11-02)


### Features

* refund a keyed admission ([d3c1aa0](https://github.com/seuros/throttle_machines/commit/d3c1aa0b95797e0574253b767e43c229ddb5de40))


### Bug Fixes

* sweep a keyed shard once an eighth of it could have recovered ([48b6ad9](https://github.com/seuros/throttle_machines/commit/48b6ad996b6ecdcf4b9b7c543d7970d0ffd8291a))

## [0.4.0](https://github.com/seuros/throttle_machines/compare/throttle-machines-v0.3.1...throttle-machines-v0.4.0) (2026-11-01)


### Features

* bound the throttle wait by the caller's deadline ([37a7784](https://github.com/seuros/throttle_machines/commit/37a7784ca6b5eed976d5b61ca4b6d0a51502a407))

## [0.3.1](https://github.com/seuros/throttle_machines/compare/throttle-machines-v0.3.0...throttle-machines-v0.3.1) (2026-10-20)


### Bug Fixes

* **core:** cap keyed GCRA storage under identity sprays ([fb8030a](https://github.com/seuros/throttle_machines/commit/fb8030a73b4dfe03497fd7550f8ee391cca41538))

## [0.3.0](https://github.com/seuros/throttle_machines/compare/throttle-machines-v0.2.1...throttle-machines-v0.3.0) (2026-10-14)


### Features

* **core:** add KeyedGcra per-key store and GcraParams::from_rate ([b7fa7a5](https://github.com/seuros/throttle_machines/commit/b7fa7a59bcc3dfb276e4fb9be3a95e38c08fe84c))


### Bug Fixes

* **core:** admit a token due now despite float rounding ([c46bd54](https://github.com/seuros/throttle_machines/commit/c46bd54e2d913ecc25c3a9fe8098a8116c1747d6))
* **core:** admit on-schedule GCRA requests despite float rounding ([5aa090e](https://github.com/seuros/throttle_machines/commit/5aa090e1562325e5d9474f3ec35cf1d22d5ccafb))

## [0.2.1](https://github.com/seuros/throttle_machines/compare/throttle-machines-v0.2.0...throttle-machines-v0.2.1) (2026-10-10)


### Performance Improvements

* **ffi:** build Decision/Outcome without a kwargs hash; adopt clippy pedantic and nursery ([23c263d](https://github.com/seuros/throttle_machines/commit/23c263da35829a9375397abaae807659ca96a1ac))

## [0.2.0](https://github.com/seuros/throttle_machines/compare/throttle-machines-v0.2.0...throttle-machines-v0.2.0) (2026-06-24)


### Features

* add matryoshka pattern with Rust native extension ([97d41a6](https://github.com/seuros/throttle_machines/commit/97d41a6ddf71e042f437c44315c40e3d30c9efe1))
* add matryoshka pattern with Rust native extension ([3f614cb](https://github.com/seuros/throttle_machines/commit/3f614cbefe8b489f6627b35b635ed954e9e84d4d))
* add native circuit breaker on shared Gate contract ([dee0b57](https://github.com/seuros/throttle_machines/commit/dee0b57b20c7c887c2e7f7e7d7d2e6a5696be118))


### Bug Fixes

* ship pure ruby fallback gem ([3a54ac3](https://github.com/seuros/throttle_machines/commit/3a54ac3dffb073ece85a10c4c35ed3c426d658f6))
