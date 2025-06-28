# 🛸 Spacecraft Manual

> **Understanding Your Fleet** - Each algorithm is a different class of spacecraft, designed for specific missions

Welcome to the ThrottleMachines fleet academy! Here you'll learn about each spacecraft class (algorithm) and when to deploy them for maximum effectiveness.

---

## 🚀 Fleet Overview

| Spacecraft Class | Algorithm | Best For | Characteristics |
|-----------------|-----------|----------|-----------------|
| **Fixed Window Shuttles** | `:fixed_window` | Quotas, billing | Hard resets at boundaries |
| **Token Bucket Freighters** | `:token_bucket` | Burst traffic | Gradual token regeneration |
| **GCRA Diplomatic Vessels** | `:gcra` | Smooth traffic | No thundering herds |
| **Sliding Window Scouts** | `:sliding_window` | Precision limiting | Exact rate tracking |

---

## 🛸 Fixed Window Shuttles

### The Analogy
Imagine a space shuttle that departs exactly every hour. It can carry 100 passengers per hour. At the stroke of each hour, the passenger count resets to zero - everyone who didn't make it must wait for the next hour.

### How It Works
```ruby
# A shuttle that allows 100 launches per hour
shuttle = ThrottleMachines.limiter("hourly_shuttle",
  limit: 100,
  period: 3600,  # 1 hour in seconds
  algorithm: :fixed_window
)

# At 13:45 - 99 requests used
shuttle.allowed? # => true (last spot!)

# At 13:59:59 - 100 requests used  
shuttle.allowed? # => false

# At 14:00:00 - Window resets!
shuttle.allowed? # => true (fresh start)
```

### Characteristics
- **Hard reset** at window boundaries
- **Simple and predictable**
- **Can cause "thundering herds"** at reset time
- **Perfect for quotas** (daily API limits, billing periods)

### Mission Profile
```ruby
class DailyMissionQuota
  def initialize
    @limiter = ThrottleMachines.limiter("daily_missions",
      limit: 1000,
      period: 86400,  # 24 hours
      algorithm: :fixed_window
    )
  end
  
  def accept_mission?
    if @limiter.allowed?
      log_mission_accepted
      true
    else
      seconds_until_reset = @limiter.retry_after
      puts "Daily quota reached. Resets in #{seconds_until_reset / 3600} hours"
      false
    end
  end
end
```

---

## 🚢 Token Bucket Freighters

### The Analogy
Picture a cargo freighter with a hold that can store 50 containers. Every second, a crane adds one new container to the hold (up to the maximum). When you need to ship cargo, you take containers from the hold. If the hold is empty, you must wait for the crane to add more.

### How It Works
```ruby
# A freighter that regenerates 1 token per second, max 50 tokens
freighter = ThrottleMachines.limiter("cargo_freighter",
  limit: 50,     # Maximum tokens in bucket
  period: 50,    # Refill rate: 50 tokens per 50 seconds = 1 token/second
  algorithm: :token_bucket
)

# Burst usage - use many tokens at once
10.times { freighter.allowed? } # All succeed if bucket was full

# Steady usage - tokens regenerate continuously
sleep 5
5.times { freighter.allowed? } # 5 new tokens available
```

### Characteristics
- **Allows bursts** up to bucket capacity
- **Smooth regeneration** over time
- **No hard resets** - continuous refill
- **Great for APIs** that allow burst usage

### Mission Profile
```ruby
class BurstCapableAPI
  def initialize
    # Allow bursts of 20, regenerate at 10 requests/minute
    @limiter = ThrottleMachines.limiter("api_bucket",
      limit: 20,      # Burst capacity
      period: 120,    # 20 tokens per 120 seconds = 10/minute sustained
      algorithm: :token_bucket
    )
  end
  
  def handle_request
    if @limiter.allowed?
      process_api_call
    else
      # Bucket empty, must wait for regeneration
      { 
        error: "Rate limited", 
        retry_after: @limiter.retry_after,
        message: "Tokens regenerating at 10/minute"
      }
    end
  end
end
```

---

## 🛸 GCRA Diplomatic Vessels

### The Analogy
GCRA ships are like diplomatic vessels at a busy spaceport. Instead of all ships trying to dock at once (causing chaos), each ship is assigned a specific arrival time based on traffic flow. The spaceport smoothly handles arrivals without congestion.

**GCRA = Generic Cell Rate Algorithm** (Don't let the name scare you!)

### How It Works
```ruby
# A diplomatic vessel managing smooth traffic flow
diplomat = ThrottleMachines.limiter("federation_embassy",
  limit: 60,      # 60 requests
  period: 60,     # per minute
  algorithm: :gcra
)

# GCRA spreads requests evenly across time
# No thundering herds, no traffic jams!
```

### The Magic of GCRA
```ruby
# Traditional rate limiting can cause "thundering herds":
# Time 0-59s: 1000 clients wait
# Time 60s: ALL 1000 clients retry at once! 💥

# GCRA prevents this by calculating individual "theoretical arrival times"
# Each client gets a personalized "next allowed time"
# Result: Smooth, distributed traffic
```

### Characteristics
- **Prevents thundering herds** completely
- **Smooth, even distribution** of requests
- **Microsecond precision** timing
- **Industry standard** for telecom and APIs

### Mission Profile
```ruby
class GalacticAPI
  def initialize
    # High-traffic API with smooth rate limiting
    @limiter = ThrottleMachines.limiter("galactic_api",
      limit: 10000,    # 10k requests
      period: 60,      # per minute
      algorithm: :gcra # Smooth traffic, no bursts
    )
  end
  
  def handle_request(client_id)
    # Each client gets their own "arrival time"
    # No synchronized retries!
    if @limiter.allowed?
      process_request
    else
      retry_time = @limiter.retry_after
      {
        error: "Rate limited",
        retry_after: retry_time,
        note: "Your personal retry time prevents server overload"
      }
    end
  end
end
```

---

## 🔭 Sliding Window Scouts

### The Analogy
Scout ships maintain a precise log of every movement in the last 60 seconds. Unlike fixed-window shuttles that reset on the hour, scouts continuously track a rolling 60-second window. It's like having a radar that shows exactly what happened in the past minute at any moment.

### How It Works
```ruby
# A scout tracking precise movements over rolling windows
scout = ThrottleMachines.limiter("recon_scout",
  limit: 10,
  period: 60,  # Rolling 60-second window
  algorithm: :sliding_window
)

# At any point, looks back exactly 60 seconds
# More precise than fixed windows, more memory intensive
```

### Characteristics
- **Most precise** rate limiting
- **True rolling window** (not approximated)
- **Higher memory usage** (tracks all events)
- **Perfect for compliance** and strict limits

### Mission Profile
```ruby
class PrecisionRateLimiter
  def initialize
    # For operations requiring exact rate compliance
    @limiter = ThrottleMachines.limiter("precision_ops",
      limit: 100,
      period: 300,  # Exactly 100 per 5 minutes
      algorithm: :sliding_window
    )
  end
  
  def execute_precision_operation
    if @limiter.allowed?
      # Guaranteed to never exceed 100 in any 5-minute window
      perform_operation
    else
      {
        error: "Precise rate limit exceeded",
        retry_after: @limiter.retry_after,
        note: "Tracking exact usage over rolling 5-minute window"
      }
    end
  end
end
```

---

## 🎯 Choosing Your Spacecraft

### Decision Matrix

| If You Need... | Choose... | Because... |
|----------------|-----------|------------|
| Daily/hourly quotas | Fixed Window | Clear reset boundaries |
| Burst allowance | Token Bucket | Handles traffic spikes |
| Smooth API traffic | GCRA | Prevents thundering herds |
| Exact compliance | Sliding Window | Precise rate tracking |
| High performance | GCRA or Token Bucket | Lower overhead |
| Simple implementation | Fixed Window | Easiest to understand |

### Quick Selection Guide

```ruby
# For API quotas (1000 requests/day)
daily_limit = ThrottleMachines.limiter("api_quota", 
  limit: 1000, period: 86400, algorithm: :fixed_window)

# For burst-capable APIs (100 burst, 10/sec sustained)
burst_api = ThrottleMachines.limiter("burst_api", 
  limit: 100, period: 10, algorithm: :token_bucket)

# For high-traffic APIs (prevent overload)
smooth_api = ThrottleMachines.limiter("smooth_api", 
  limit: 1000, period: 60, algorithm: :gcra)

# For compliance/audit (exact limits)
compliance = ThrottleMachines.limiter("compliance", 
  limit: 50, period: 300, algorithm: :sliding_window)
```

---

## 🚀 Advanced Maneuvers

### Combining Algorithms
```ruby
class HybridDefenseSystem
  def initialize
    # Layer different algorithms for comprehensive protection
    @quotas = ThrottleMachines.limiter("daily_quota", 
      limit: 10000, period: 86400, algorithm: :fixed_window)
    
    @burst_control = ThrottleMachines.limiter("burst_control",
      limit: 100, period: 10, algorithm: :token_bucket)
    
    @smooth_traffic = ThrottleMachines.limiter("smooth_traffic",
      limit: 60, period: 60, algorithm: :gcra)
  end
  
  def process_request
    # Must pass all checks
    return quota_exceeded unless @quotas.allowed?
    return burst_limit_hit unless @burst_control.allowed?
    return traffic_limit unless @smooth_traffic.allowed?
    
    handle_request
  end
end
```

---

## 📚 Further Reading

- **[⚡ Warp Drive Configuration](WARP_DRIVE.md)** - Configure storage backends
- **[🛡️ Shield Protocols](SHIELD_PROTOCOLS.md)** - Circuit breakers
- **[🎮 Command Examples](COMMAND_EXAMPLES.md)** - Real-world scenarios

---

**"Know your spacecraft, know your mission, know victory."**

*— Fleet Admiral's Handbook, Section 3.2*