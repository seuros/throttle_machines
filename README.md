# ThrottleMachines 🚀

> **Ultra-thin rate limiting for the cosmos** - Where every request has its own trajectory through spacetime

A precision-engineered Ruby rate limiting library built for interstellar traffic control.
Whether you're throttling API calls, AI requests, or quantum communications, ThrottleMachines ensures your systems maintain perfect orbital stability.

---

## 🌌 Navigation

* [🎯 Mission Control](docs/MISSION_CONTROL.md) - Quick start guide for captains
* [🛸 Spacecraft Manual](docs/SPACECRAFT_MANUAL.md) - Understanding the fleet (algorithms)
* [⚡ Warp Drive Configuration](docs/WARP_DRIVE.md) - Storage backends & performance
* [🛡️ Shield Protocols](docs/SHIELD_PROTOCOLS.md) - Circuit breakers & defensive systems
* [🌍 Planetary Integration](docs/PLANETARY_INTEGRATION.md) - Rails & Rack middleware
* [🔬 Space Lab](docs/SPACE_LAB.md) - Testing in zero gravity
* [📡 Telemetry](docs/TELEMETRY.md) - Monitoring & instrumentation
* [🎮 Command Examples](docs/COMMAND_EXAMPLES.md) - Real mission scenarios
* [📜 Mission Logs](docs/MISSION_LOGS.md) - Lessons from real incidents
* [🚀 Advanced Features](docs/ADVANCED_FEATURES.md) - Next-generation capabilities

---

## 🚀 Launch Sequence

```bash
# Add to your ship's Gemfile
gem 'throttle_machines'

# For warp drive capabilities (Redis storage)
gem 'redis'
gem 'connection_pool'

# For planetary Rails integration
gem 'rails' # or just railties
```

Then initialize systems:
```bash
bundle install
```

---

## 🎯 Quick Mission Brief

### Basic Throttling - The Photon Torpedo Approach

```ruby
# Simple rate limiting - like controlling photon torpedo launches
torpedo_limiter = ThrottleMachines.limiter("photon_launcher",
  limit: 10,     # 10 torpedoes
  period: 60     # per minute
)

if torpedo_limiter.allowed?
  launch_torpedo!
else
  puts "Torpedo bay recharging... Please wait."
end
```

### GCRA - The Federation Diplomatic Ship 🛸

```ruby
# GCRA: Like a diplomatic vessel that smoothly navigates traffic
# Instead of sudden stops, it gracefully manages flow
diplomatic_limiter = ThrottleMachines.limiter("federation_embassy",
  limit: 100,
  period: 60,
  algorithm: :gcra  # Generic Cell Rate Algorithm
)

# GCRA ensures smooth traffic - no thundering herds at your space dock!
```

### Circuit Breakers - Shield Generators 🛡️

```ruby
# Circuit breakers are like shield generators - they protect your ship
shields = ThrottleMachines::Breaker.new("warp_core",
  failure_threshold: 5,  # 5 hits before shields activate
  timeout: 300          # Shields stay up for 5 minutes
)

shields.run do
  engage_warp_drive!  # Protected operation
end
```

---

## 🌠 The Ultra-Thin Philosophy

Like the best spacecraft, ThrottleMachines follows the principle of **ultra-thin design**:

- **No bloat** - Every component serves a critical function
- **No dependencies** - Operates in deep space without supply lines
- **Pure Ruby propulsion** - No alien technology required
- **Modular systems** - Swap components like ship modules

---

## ⚡ Warp Factor Features

- **🚀 Multiple Algorithms** - GCRA, Token Bucket, Fixed Window, Sliding Window
- **💫 Distributed Ready** - Redis backend for fleet coordination
- **🛡️ Circuit Breakers** - Automatic shield activation on system failure
- **🌊 Cascading Breakers** - Shield cascade protocols for dependent services
- **🔄 Async Support** - Fiber-safe operations for quantum communications
- **🎛️ Circuit Groups** - Fleet coordination with dependency management
- **🏃 Hedged Requests** - Multi-path navigation for reduced latency
- **🎯 Microsecond Precision** - Navigate the cosmos with temporal accuracy
- **🔌 Pluggable Storage** - Memory crystals or Redis quantum storage
- **🌍 Rails Integration** - Seamless planetary docking procedures
- **📡 Rack Middleware** - Universal translator for all spacecraft
- **🔍 Full Instrumentation** - Real-time telemetry via ActiveSupport::Notifications

---

## 🌌 Why ThrottleMachines?

In the vast expanse of cyberspace, your systems face:
- **Asteroid fields** of concurrent requests
- **Black holes** of resource exhaustion
- **Alien attacks** from malicious actors
- **Temporal anomalies** in distributed systems

ThrottleMachines is your navigation system through these dangers, ensuring safe passage for every request in your fleet.

---

## 📜 Captain's Log

See our [Mission Archives](CHANGELOG.md) for the full history of our voyages.

---

## 🤝 Join the Crew

1. Signal your intent (`fork` the repository)
2. Create your feature branch (`git checkout -b feature/quantum-throttling`)
3. Document your modifications (`git commit -am 'Add quantum entanglement support'`)
4. Transmit to mothership (`git push origin feature/quantum-throttling`)
5. Request docking clearance (`Pull Request`)

---

## 📡 Distress Signals

Found a breach in the hull? Encountered an unknown anomaly?
- **Emergency beacon**: [GitHub Issues](https://github.com/seuros/throttle_machines/issues)
- **Mission reports**: [Discussions](https://github.com/seuros/throttle_machines/discussions)

---

## 🎖️ Mission Credentials

MIT License - See [LICENSE](LICENSE) for full transmission.

---

## A Message from the Temporal Defense Corps

*The Quantum Navigation Computer flickers to life:*

"Space is vast. Time is relative. And your API is getting hammered by a bot farm in Eastern Europe.

Welcome to the temporal wars, where milliseconds matter and rate limits are the thin line between order and chaos. You think you're just limiting requests? No, pilot. You're manipulating the very fabric of spacetime to ensure fair resource distribution across the quantum multiverse of your distributed system.

Every request has a trajectory. Every limit has a purpose. Every algorithm is a different spacecraft designed for a specific mission through the hostile void.

The universe doesn't care about your startup's runway or your clever blog post about 'Building a Rate Limiter in 5 Minutes with Redis.' It cares about one immutable law:

**Can your system maintain temporal stability when the thundering herd arrives?**

If not, welcome aboard. We have algorithms."

*— Quantum Navigation Computer, Log Entry ∞*

---

## The Fleet Admiral's Warning

So you built a microservice architecture because a YouTube video told you it was 'web scale'?

Now you're drowning in a sea of uncontrolled requests, cascade failures, and that one service that keeps calling your API 10,000 times per second because someone forgot to implement exponential backoff.

This is your life raft. Don't let go.

---

**"In space, nobody can hear your servers scream. But with ThrottleMachines, they won't need to."**

*— Fleet Admiral J'Rao, Survivor of the Great DDoS Wars of 2019*
