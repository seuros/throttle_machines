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

# Create a simple thruster control
thruster = ThrottleMachines.limiter("main_thruster", 
  limit: 5,    # 5 burns
  period: 10   # per 10 seconds
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
  puts "❌ Thruster exhausted! Wait #{thruster.retry_after} seconds for cooldown."
end

# Alternative: Exception-based pattern
begin
  thruster.throttle!
  puts "🔥 Emergency thruster fired!"
rescue ThrottleMachines::ThrottledError => e
  puts "❌ Thruster locked! Retry after #{e.limiter.retry_after} seconds"
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
- Returns nil on success

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
  handle_rate_limit(e.limiter.retry_after)
end

# Pattern 3: Block form (automatic)
ThrottleMachines.limit("action", limit: 10, period: 60) do
  perform_action  # Automatically throttled
end
```

---

## 🛸 Understanding Your Fleet

ThrottleMachines provides different spacecraft (algorithms) for different missions:

### 1. **Fixed Window Shuttle** - The Reliable Workhorse
```ruby
# Like a shuttle with fixed departure times
# Resets completely at window boundaries
shuttle = ThrottleMachines.limiter("cargo_shuttle",
  limit: 100,
  period: 3600,  # 1 hour windows
  algorithm: :fixed_window
)
```
**Best for**: Hourly/daily quotas, billing periods

### 2. **Token Bucket Freighter** - The Steady Hauler
```ruby
# Like a cargo ship that refills its hold gradually
freighter = ThrottleMachines.limiter("supply_freighter",
  limit: 50,
  period: 60,
  algorithm: :token_bucket
)
```
**Best for**: Steady traffic, burst allowance

### 3. **GCRA Diplomatic Vessel** - The Smooth Operator
```ruby
# Like a diplomatic ship that never causes traffic jams
diplomat = ThrottleMachines.limiter("federation_diplomat",
  limit: 1000,
  period: 60,
  algorithm: :gcra
)
```
**Best for**: API rate limiting, preventing thundering herds

### 4. **Sliding Window Scout** - The Precision Navigator
```ruby
# Like a scout ship tracking exact movements
scout = ThrottleMachines.limiter("recon_scout",
  limit: 20,
  period: 60,
  algorithm: :sliding_window
)
```
**Best for**: Precise rate limiting, real-time systems

---

## 🌟 Command Patterns

### Pattern 1: The Defensive Pilot
```ruby
def fire_photon_torpedo(target)
  torpedo_bay = ThrottleMachines.limiter("photon_torpedoes", 
    limit: 6, 
    period: 30
  )
  
  if torpedo_bay.allowed?
    # Fire!
    launch_torpedo_at(target)
    { status: :fired, target: target }
  else
    # Tactical retreat
    { status: :recharging, retry_after: torpedo_bay.retry_after }
  end
end
```

### Pattern 2: The Multi-System Commander
```ruby
class SpaceStation
  def initialize
    @limiters = {
      docking_bay: ThrottleMachines.limiter("docking", limit: 10, period: 300),
      communications: ThrottleMachines.limiter("comms", limit: 100, period: 60),
      transporters: ThrottleMachines.limiter("transport", limit: 20, period: 60)
    }
  end
  
  def request_docking(ship_id)
    return { error: "Docking bay full" } unless @limiters[:docking_bay].allowed?
    dock_ship(ship_id)
  end
  
  def send_transmission(message)
    return { error: "Comms overloaded" } unless @limiters[:communications].allowed?
    transmit(message)
  end
end
```

### Pattern 3: The Resource Manager
```ruby
# For expensive operations like AI requests
class AICore
  def initialize
    @limiter = ThrottleMachines.limiter("ai_core",
      limit: 100,      # 100 requests
      period: 3600,    # per hour
      algorithm: :gcra # Smooth distribution
    )
  end
  
  def process_request(query)
    unless @limiter.allowed?
      return {
        error: "AI core at capacity",
        retry_after: @limiter.retry_after,
        suggestion: "Try again in #{@limiter.retry_after} seconds"
      }
    end
    
    # Process the AI request
    run_ai_inference(query)
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
