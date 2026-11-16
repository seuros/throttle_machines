# 🎯 Mission Control

> **Captain's Quick Start Guide** - From launch pad to orbit in 5 minutes

Welcome aboard, Captain! This guide will have you commanding the ThrottleMachines fleet faster than a photon through a vacuum.

---

## 🚦 Pre-Flight Checklist

```ruby
# Gemfile - Your ship's manifest
gem 'throttle_machines'
gem 'redis'  # Optional: For distributed fleet operations
```

```bash
bundle install
```

---

## 🎮 Basic Flight Controls

### Your First Launch - The Space Cadet Special

```ruby
require 'throttle_machines'

# Every span is Integer nanoseconds
NS = ThrottleMachines::NS_PER_SECOND # 1_000_000_000

# Create a simple thruster control
thruster = ThrottleMachines.limiter("main_thruster",
  limit: 5,        # 5 burns
  period: 10 * NS  # per 10 seconds
)

# Fire the thrusters! (Check and consume pattern)
5.times do
  if thruster.allow?  # Check if we can fire
    thruster.throttle!  # Consume one charge
    puts "🔥 Thruster fired!"
  else
    puts "⚠️  Thruster cooling down..."
  end
end

# Try one more...
if thruster.allow?
  thruster.throttle!
  puts "🔥 Thruster fired!"
else
  puts "❌ Thruster exhausted! Wait #{thruster.retry_after.ceildiv(NS)}s for cooldown."
end

# Alternative: Exception-based pattern
begin
  thruster.throttle!
  puts "🔥 Emergency thruster fired!"
rescue ThrottleMachines::ThrottledError => e
  puts "❌ Thruster locked! Retry after #{e.retry_after} ns"
end
```

---

## ⚡ Understanding the Controls

### The Two Key Methods

**`allow?`** - The Scanner
- Checks if you have capacity remaining
- Does NOT consume any of your limit
- Returns true/false
- Safe to call multiple times

**`throttle!`** - The Trigger
- Checks AND consumes one unit from your limit
- Raises `ThrottledError` if over limit
- Use this when you actually perform the action
- Takes an optional block and returns its value (nil without one)

**`retry_after`** - The Countdown
- Integer nanoseconds until the next call is admitted (zero when one is now)
- Divide with `ceildiv(NS)` only when a human (or a `Retry-After` header) wants seconds

### Usage Patterns

```ruby
# Pattern 1: Check first, then consume
if limiter.allow?
  limiter.throttle!  # Must consume!
  perform_action
end

# Pattern 2: Just throttle (with exceptions)
begin
  limiter.throttle!
  perform_action
rescue ThrottleMachines::ThrottledError => e
  handle_rate_limit(e.retry_after) # Integer nanoseconds
end

# Pattern 3: Block form (automatic)
ThrottleMachines.limit("action", limit: 10, period: 60 * NS) do
  perform_action  # Automatically throttled
end
```

---

## 🛸 Understanding Your Fleet

ThrottleMachines provides three spacecraft (algorithms) for different missions. Without `algorithm:`, a limiter flies `config.default_algorithm` (`:fixed_window` out of the box):

### 1. **Fixed Window Shuttle** - The Reliable Workhorse
```ruby
# Like a shuttle with fixed departure times
# Resets completely at window boundaries
shuttle = ThrottleMachines.limiter("cargo_shuttle",
  limit: 100,
  period: 3600 * NS,  # 1 hour windows
  algorithm: :fixed_window
)
```
**Best for**: Hourly/daily quotas, billing periods

### 2. **Token Bucket Freighter** - The Steady Hauler
```ruby
# Like a cargo ship that refills its hold gradually
freighter = ThrottleMachines.limiter("supply_freighter",
  limit: 50,
  period: 60 * NS,
  algorithm: :token_bucket
)
```
**Best for**: Steady traffic, burst allowance

### 3. **GCRA Diplomatic Vessel** - The Smooth Operator
```ruby
# Like a diplomatic ship that never causes traffic jams
diplomat = ThrottleMachines.limiter("federation_diplomat",
  limit: 1000,
  period: 60 * NS,
  algorithm: :gcra
)
```
**Best for**: API rate limiting, preventing thundering herds

> **Decommissioned: the Sliding Window Scout.** `:sliding_window` is no longer in the fleet;
> asking for it raises `RangeError`. For precise, even spacing, fly the GCRA vessel.

---

## 🌟 Command Patterns

### Pattern 1: The Defensive Pilot
```ruby
def fire_photon_torpedo(target)
  torpedo_bay = ThrottleMachines.limiter("photon_torpedoes",
    limit: 6,
    period: 30 * NS
  )

  torpedo_bay.throttle! do
    # Fire!
    launch_torpedo_at(target)
    { status: :fired, target: target }
  end
rescue ThrottleMachines::ThrottledError => e
  # Tactical retreat
  { status: :recharging, retry_after: e.retry_after } # Integer nanoseconds
end
```

### Pattern 2: The Multi-System Commander
```ruby
class SpaceStation
  def initialize
    @limiters = {
      docking_bay: ThrottleMachines.limiter("docking", limit: 10, period: 300 * NS),
      communications: ThrottleMachines.limiter("comms", limit: 100, period: 60 * NS),
      transporters: ThrottleMachines.limiter("transport", limit: 20, period: 60 * NS)
    }
  end

  def request_docking(ship_id)
    @limiters[:docking_bay].throttle! { dock_ship(ship_id) }
  rescue ThrottleMachines::ThrottledError
    { error: "Docking bay full" }
  end

  def send_transmission(message)
    @limiters[:communications].throttle! { transmit(message) }
  rescue ThrottleMachines::ThrottledError
    { error: "Comms overloaded" }
  end
end
```

### Pattern 3: The Resource Manager
```ruby
# For expensive operations like AI requests
class AICore
  def initialize
    @limiter = ThrottleMachines.limiter("ai_core",
      limit: 100,         # 100 requests
      period: 3600 * NS,  # per hour
      algorithm: :gcra    # Smooth distribution
    )
  end

  def process_request(query)
    # Process the AI request
    @limiter.throttle! { run_ai_inference(query) }
  rescue ThrottleMachines::ThrottledError => e
    {
      error: "AI core at capacity",
      retry_after: e.retry_after, # Integer nanoseconds
      suggestion: "Try again in #{e.retry_after.ceildiv(NS)} seconds"
    }
  end
end
```

---

## 🎯 Mission Objectives Achieved

✅ Launched your first rate limiter
✅ Understood the spacecraft types (algorithms)
✅ Learned basic command patterns

---

## 🚀 Next Missions

Ready for advanced maneuvers?

- **[🛸 Spacecraft Manual](SPACECRAFT_MANUAL.md)** - Deep dive into each algorithm
- **[⚡ Warp Drive Configuration](WARP_DRIVE.md)** - Redis and distributed operations
- **[🛡️ Shield Protocols](SHIELD_PROTOCOLS.md)** - Circuit breakers for system protection

---

**"A smooth launch is the first step to conquering the galaxy."**

*— Academy Training Manual, Chapter 1*
