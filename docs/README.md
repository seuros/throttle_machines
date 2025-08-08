# 🌌 ThrottleMachines Documentation

> **Navigation Computer** - Your guide through the cosmos of rate limiting

Welcome to the ThrottleMachines documentation system. This is your complete guide to mastering rate limiting, circuit breakers, and traffic management in the Ruby universe.

---

## 📚 Documentation Structure

### 🚀 Getting Started
- **[🎯 Mission Control](MISSION_CONTROL.md)** - Quick start guide for new captains
  - Basic flight controls
  - Your first rate limiter
  - Understanding the fleet

### 🛸 Core Concepts
- **[🛸 Spacecraft Manual](SPACECRAFT_MANUAL.md)** - Deep dive into algorithms
  - Fixed Window Shuttles
  - Token Bucket Freighters
  - GCRA Diplomatic Vessels
  - Sliding Window Scouts

### ⚙️ Configuration
- **[⚡ Warp Drive Configuration](WARP_DRIVE.md)** - Storage backends
  - Memory crystals (default)
  - Redis quantum core
  - Performance tuning

- **[🛡️ Shield Protocols](SHIELD_PROTOCOLS.md)** - Circuit breakers
  - Basic shield configuration
  - Cascading defense systems
  - Adaptive protection

### 🌍 Integration
- **[🌍 Planetary Integration](PLANETARY_INTEGRATION.md)** - Framework integration
  - Rails controller integration
  - Rack middleware setup
  - Multi-tenant configurations

### 🔬 Development
- **[🔬 Space Lab](SPACE_LAB.md)** - Testing guide
  - Testing rate limiters
  - Testing circuit breakers
  - Performance benchmarks
  - Time travel utilities

### 📊 Operations
- **[📡 Telemetry](TELEMETRY.md)** - Monitoring & metrics
  - Dashboard configuration
  - Alerting systems
  - Health checks
- **[🔍 Instrumentation](INSTRUMENTATION.md)** - Event tracking & observability
  - ActiveSupport::Notifications integration
  - Available events
  - APM integration
  - Custom backends

### 💡 Examples
- **[🎮 Command Examples](COMMAND_EXAMPLES.md)** - Real-world scenarios
  - API gateway defense
  - AI service rate limiting
  - Multi-tenant platforms
  - Geographic routing
  - WebSocket management

### 🚀 Advanced Features
- **[🚀 Advanced Features](ADVANCED_FEATURES.md)** - Next-generation capabilities
  - Cascading circuit breakers
  - Async/fiber-safe operations  
  - Circuit groups with dependencies
  - Hedged requests for latency reduction

### 📜 Historical Records
- **[📜 Mission Logs](MISSION_LOGS.md)** - Real incidents from the field
  - The Great Twitter Rationing (2023)
  - Cloudflare Shield Malfunction (2024)
  - OpenAI Station Crash (2024)
  - Thundering Herd Prevention

---

## 🎓 Learning Path

### For New Pilots (Beginners)
1. Start with **[Mission Control](MISSION_CONTROL.md)** - Get flying in 5 minutes
2. Read **[Spacecraft Manual](SPACECRAFT_MANUAL.md)** - Understand the algorithms
3. Try **[Command Examples](COMMAND_EXAMPLES.md)** - See real implementations

### For Engineers (Intermediate)
1. Master **[Warp Drive Configuration](WARP_DRIVE.md)** - Configure storage
2. Study **[Shield Protocols](SHIELD_PROTOCOLS.md)** - Implement circuit breakers
3. Explore **[Planetary Integration](PLANETARY_INTEGRATION.md)** - Rails/Rack setup

### For Commanders (Advanced)
1. Design with **[Command Examples](COMMAND_EXAMPLES.md)** - Complex scenarios
2. Monitor with **[Telemetry](TELEMETRY.md)** - Production insights
3. Test with **[Space Lab](SPACE_LAB.md)** - Comprehensive testing

---

## 🔍 Quick Concept Reference

### Rate Limiting Algorithms

| Algorithm | Space Analogy | Use Case |
|-----------|---------------|----------|
| **Fixed Window** | Shuttle with scheduled departures | Quotas, billing periods |
| **Token Bucket** | Cargo ship with gradual loading | APIs with burst capacity |
| **GCRA** | Diplomatic vessel with smooth traffic flow | High-traffic APIs, no thundering herds |
| **Sliding Window** | Scout ship with precise tracking | Compliance, exact limits |

### Key Components

| Component | Purpose | Documentation |
|-----------|---------|---------------|
| **Limiters** | Control request rates | [Spacecraft Manual](SPACECRAFT_MANUAL.md) |
| **Breakers** | Protect failing services | [Shield Protocols](SHIELD_PROTOCOLS.md) |
| **Storage** | State persistence | [Warp Drive](WARP_DRIVE.md) |
| **Middleware** | HTTP integration | [Planetary Integration](PLANETARY_INTEGRATION.md) |

---

## 💫 The Philosophy

ThrottleMachines follows the **ultra-thin** design principle:

1. **No bloat** - Every feature has a purpose
2. **No magic** - Clear, understandable behavior  
3. **No dependencies** - Pure Ruby with optional enhancements
4. **No compromises** - Performance and precision

---

## 🆘 Getting Help

- **Issues**: [GitHub Issues](https://github.com/seuros/throttle_machines/issues)
- **Discussions**: [GitHub Discussions](https://github.com/seuros/throttle_machines/discussions)
- **Examples**: See [Command Examples](COMMAND_EXAMPLES.md)

---

## 📝 Contributing to Docs

Found an error? Have a better analogy? Want to add an example?

1. Fork the repository
2. Edit the relevant `.md` file in `docs/`
3. Submit a pull request

Remember: Keep the space theme consistent and make technical concepts accessible!

---

**"Documentation is the star map that guides future travelers through your code cosmos."**

*— Ancient Programmer Wisdom*
