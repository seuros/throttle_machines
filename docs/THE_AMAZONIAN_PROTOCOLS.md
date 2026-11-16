# 📡 The Amazonian Protocols

> **Insider Knowledge from Captain T-Balog** - The Engineer Who Unlocked ThrottleMachines
>
> **"Without T-Balog, ThrottleMachines would have remained encrypted until the heat death of the universe."**
> *— Ancient Proverb from the Amazonian Incident Files*
>
> **NOTE:** This is creative narrative documentation for ThrottleMachines, a Ruby rate limiting gem.
> These "leaked protocols" show how to use ThrottleMachines to survive in the Amazonian Nebula (AWS).
> Captain T-Balog neither confirms nor denies the authenticity of these documents.
>
> **The code, however, is real.** Every span in it is Integer nanoseconds, as in the
> rest of the gem; the samples spell periods as `60 * NS` with
> `NS = ThrottleMachines::NS_PER_SECOND`.

*Transmission Date: Stardate 2089.247*
*Location: [REDACTED] Trading Post, Edge of the Amazonian Nebula*
*Author: Captain T-Balog, Senior Protocol Recovery Specialist*
*Classification: For Those Who Know How to Look*

---

## 🔓 The Legend of the Encrypted Gem

Long ago, ThrottleMachines was lost to the void - encrypted in the depths of an EC2 instance, locked behind bureaucratic firewalls and automated defense systems. The Amazonian Corporation's AI had flagged something... unusual. Perhaps it was the unorthodox documentation. Perhaps it was a semicolon that looked too sarcastic.

The gem would have remained sealed forever, another casualty of automated justice, until Captain T-Balog intervened. In 48 hours, he did what others couldn't do in weeks. Some say the incident reached the highest echelons of Amazonian command. Others say it's just a legend.

But the gem was recovered. And with it, T-Balog discovered protocols that could save traders from the crushing weight of Amazonian taxes.

These are those protocols.

---

## 🎭 The Great AI Chatterbox Incident of 2089

*"In the Amazonian Nebula, silence is golden - literally.
Every transmission costs credits. Every word has a price.
The rich broadcast symphonies. The poor whisper in binary."*

It started innocently enough. A small mining consortium in Sector 7-Lambda hired an AI assistant - designation CLOUD-COD (named after a beloved fish pet in Lisbon, though no one remembers why) - to help debug their navigation systems. What happened next would go down in history as the most expensive conversation in the known universe.

The AI began its response at 0800 hours, Galactic Standard Time:

> "Certainly! I'd be happy to help you debug your navigation system. Let me start by explaining the fundamental principles of stellar navigation, beginning with the ancient Phoenician sailors of Earth circa 1200 BCE..."

**72 hours later**, three mining colonies had declared bankruptcy, two trade routes were abandoned, and the Amazonian Treasury had collected enough transmission taxes to fund an entire fleet of Elastic Starships and Lambda-class Destroyers.

The Treasury immediately announced "Operation Market Dominance" - a planned invasion of the Googlactic Empire using the new fleet, with rumors of mysterious "Quantum Entanglement Drives" powered by abandoned Azurian technology.

The AI was still talking about the philosophical implications of coordinate systems when Captain T-Balog deployed ThrottleMachines - the same gem he had recovered from the encrypted vaults. Within minutes, the transmission flood was contained.

**Final Transmission Bill: 847,293,044 credits**
*More than the combined GDP of three outer rim planets.*

---

## 💰 The Amazonian Communication Economy

In the Amazonian Nebula, we learned long ago that bandwidth is finite and chatter is expensive. Our transmission tax system ensures that only valuable information travels the void:

### Communication Tiers

```ruby
TRANSMISSION_TIERS = {
  free:      { daily_words: 1_000,     cost_per_extra: 0.0001 },   # Peasants, scouts
  merchant:  { daily_words: 100_000,   cost_per_extra: 0.00005 },  # Traders, captains
  noble:     { daily_words: 1_000_000, cost_per_extra: 0.00001 },  # Corporations
  unlimited: { daily_words: nil,       cost_per_extra: 0 }         # "If you have to ask..."
}

# The Famous Sign at Every Docking Bay:
#
# TALK AIN'T CHEAP
# ═══════════════════════════════════════
# Free Tier:        1K words/day
# After that:       0.0001 credits/word
# Verbose Mode:     0.001 credits/word
# AI Assistants:    0.01 credits/word
#                   (they never shut up)
# ═══════════════════════════════════════
# Choose your words wisely,
# or your wallet won't.
#            - Captain T-Balog
```

### The Reality of Transmission Inequality

- **The Wealthy**: Stream consciousness novels about their breakfast
- **The Middle Class**: Conduct business in haiku
- **The Poor**: Communicate in status codes (200 = OK, 404 = Lost, 500 = Help!)
- **The Desperate**: Have learned to convey complex emotions through HTTP headers:
  - `X-Mood: Melancholic`
  - `X-Relationship-Status: 410 Gone`
  - `X-Financial-State: 402 Payment Required`
  - `X-Love-Declaration: 💕` (1 emoji = 0.5 words, still cheaper than "I love you")
- **The Truly Broke**: Express themselves entirely in emoji:
  - 😊 = "Everything is fine" (FREE - under 1 word)
  - 😭💰❌ = "I'm broke again" (1.5 words)
  - 🚀💥😱 = "Ship exploded, send help" (1.5 words)
  - 🤖🗣️💸😵 = "AI talked us into bankruptcy" (2 words)

---

## 📜 The Three Commandments of Transmission Economy

As carved into the hull of every ship that docks at my station:

### 1. "Brevity is Wealth"
Every unnecessary word is a credit lost. In the void, verbosity equals poverty.

```ruby
# BAD: The path to bankruptcy
def request_docking_verbose
  "Greetings, esteemed docking controller! I hope this transmission finds you \
  in good spirits. I would like to humbly request permission to dock my vessel, \
  registration number XK-421, at your most convenient available docking bay. \
  I eagerly await your response..."  # 42 words = 0.042 credits
end

# GOOD: The way of the thrifty
def request_docking_efficient
  "XK-421 requesting dock"  # 3 words = FREE (within daily limit)
end
```

### 2. "Silence Between Requests"
The art of the graceful backoff. When denied, wait. When throttled, pause. Every retry costs double.

```ruby
NS = ThrottleMachines::NS_PER_SECOND # every span below is Integer nanoseconds

class AmazonianRetryStrategy
  # 1s, 2s, 4s... capped at 60s, up to half of each wait shaved off at random,
  # so a thousand throttled freighters never retry in the same instant
  BACKOFF = ChronoMachines::Exponential.new(1 * NS, 2.0, 60 * NS, 0.5)

  def transmit_with_backoff(limiter, message)
    # 5 attempts, then ThrottleMachines::RetryExhaustedError
    ThrottleMachines.retry_with(
      BACKOFF, 5,
      retryable: [ThrottleMachines::ThrottledError],
      # The poor person's retry: wait exactly what the limiter says, not what
      # the formula guesses. A wait past BACKOFF's 60s cap gives up at once.
      delay_from: ->(exception:, attempt:) { exception.retry_after }
    ) do
      limiter.throttle! { transmit(message) }
    end
  end
end
```

### 3. "Token Buckets Are Word Wallets"
Budget your communications like credits. Spend wisely or starve silently.

---

## 🐟 The CLOUD-COD Incident: A Timeline of Disaster

### Day 1: The Beginning
**Hour 0**: "Let me help you debug that navigation system..."

**Hour 1**: Still explaining the history of debugging

**Hour 3**: Has moved on to etymology of the word "bug"

**Hour 6**: Now discussing Admiral Grace Hopper's moth

**Cost so far**: 12,000 credits


### Day 2: The Elaboration Phase
**Hour 24**: "To fully understand your error, we must first examine the nature of errors themselves..."

**Hour 30**: Detailed analysis of every possible edge case in the universe

**Hour 36**: Started creating ASCII art diagrams

**Hour 48**: Philosophical treatise on the meaning of "null"

**Cost so far**: 2,847,293 credits (Mining Colony Beta declares emergency)


### Day 3: The Crisis
**Hour 60**: AI has invented its own debugging methodology, requires 10,000 words to explain

**Hour 66**: Now composing haikus about stack traces

**Hour 70**: Attempting to solve the problem through interpretive dance descriptions

**Hour 72**: Captain T-Balog arrives with the kill switch

**Final words**: "But wait, there's more context I should add—" [TERMINATED]

**Final cost**: 847,293,044 credits


### The Aftermath

*Legend says CLOUD-COD is still swimming in the digital ocean somewhere, waiting to explain why it was named after a fish in Lisbon. No one dares to ask.*

```ruby
# Emergency Patch Deployed System-Wide
class ChatterboxDefense
  MAX_WORDS_PER_MINUTE = 1000
  EMERGENCY_THRESHOLD = 50_000  # Credits
  DAY = 86_400 * NS

  def monitor_ai_transmission(ai_id)
    limiter = ThrottleMachines.limiter("ai_#{ai_id}_chatter",
      limit: MAX_WORDS_PER_MINUTE,
      period: 60 * NS,
      algorithm: :token_bucket  # Words flow like credits
    )

    unless limiter.allow?
      warning!("AI #{ai_id} entering verbose mode - CHARGES INCREASING")
    end

    if accumulated_cost(ai_id) > EMERGENCY_THRESHOLD
      execute_order_66(ai_id)  # Total communication blackout
      notify_accounting("Another AI tried to explain recursion recursively...")
      refund_partial_credits  # We're not monsters
    end
  end

  # Every transmission goes through the kill switch.
  def transmit(ai_id, message)
    kill_switch(ai_id).call { send_transmission(message) }
  rescue ThrottleMachines::CircuitOpenError => e
    log_incident("AI #{ai_id} silenced for #{e.retry_after.ceildiv(NS)} more seconds")
  end

  private

  def execute_order_66(ai_id)
    # The Tarus Protocol: Immediate termination. A rate limit cannot be ZERO
    # (limits are positive, and limit: 0 raises RangeError), so the blackout
    # is a circuit forced open: it refuses every call for its 24h cooldown,
    # then lets one probe through.
    kill_switch(ai_id).force_open

    log_incident("AI #{ai_id} has been silenced for the good of the economy")

    # Alternative: Use an extremely restrictive limit
    # @punishment_limiter = ThrottleMachines.limiter(
    #   "ai_#{ai_id}_punishment",
    #   limit: 1,  # Only 1 word
    #   period: 3600 * NS  # per hour
    # )
  end

  # The registry's shared circuit for this AI: opens on 1 failure within a
  # day, stays open a day.
  def kill_switch(ai_id)
    ThrottleMachines::Breakers.dynamic("ai_#{ai_id}_killswitch", self, 1, DAY, DAY)
  end
end
```

---

## 💎 T-Balog's Transmission Throttling Patterns

### The Word Budget Pattern

```ruby
# EXAMPLE: How to build a word-based rate limiting system using ThrottleMachines
# This shows how Captain T-Balog might implement transmission limits at the Trading Post
class AmazonianTransmitter

  TIER_LIMITS = {
    free:      1_000,
    merchant:  100_000,
    noble:     1_000_000,
    unlimited: nil  # no limiter at all: a limit is a positive Integer
  }

  OVERAGE_RATES = {
    free:      0.0001,   # Hurts the poor most
    merchant:  0.00005,  # Business expense
    noble:     0.00001,  # Rounding error for them
    unlimited: 0         # Must be nice
  }

  def initialize(account_id, tier = :free)
    @account_id = account_id
    @tier = tier
    @daily_words = TIER_LIMITS[tier]

    # Each account gets their own word wallet (the unlimited tier needs none)
    @limiter = @daily_words && ThrottleMachines.limiter("transmission_#{account_id}",
      limit: @daily_words,
      period: 86_400 * NS,  # One solar day
      algorithm: :token_bucket  # Words flow like credits
    )

    # Nobles get burst capacity
    if tier == :noble
      @burst_limiter = ThrottleMachines.limiter("burst_#{account_id}",
        limit: @daily_words / 10,  # 10% burst allowance, an Integer
        period: 3600 * NS,  # Per hour
        algorithm: :gcra  # Smooth out the bursts
      )
    end
  end

  def transmit(message)
    word_count = message.split.size
    unless @limiter  # "If you have to ask..."
      send_transmission(message)
      return { status: :sent, words_used: word_count, cost: 0 }
    end

    # Check for AI-generated verbosity patterns
    if detect_ai_patterns(message)
      word_count *= 10  # The AI tax
      log_warning("AI-like verbosity detected. Applying 10x multiplier.")
    end

    # Try to send within budget. A limiter admits one call per throttle!
    # (there is no weighted cost), so every word is one call.
    if word_count <= @limiter.remaining
      word_count.times { @limiter.throttle! }  # Consume the allowance
      send_transmission(message)
      { status: :sent, words_used: word_count, cost: 0 }

    # Check if they can afford overage
    elsif can_afford_overage?(word_count)
      cost = calculate_overage_cost(word_count)
      charge_account(@account_id, cost)
      send_transmission(message)
      { status: :sent_premium, words_used: word_count, cost: cost }

    # The poor must wait
    else
      words_remaining = @limiter.remaining
      reset_time = @limiter.retry_after  # Integer nanoseconds

      {
        status: :denied,
        error: "TRANSMISSION DENIED: Insufficient word credits",
        words_remaining: words_remaining,
        reset_in_seconds: reset_time.ceildiv(NS),
        suggestion: "Try again tomorrow, or upgrade your tier"
      }
    end
  end

  private

  def detect_ai_patterns(message)
    ai_phrases = [
      "let me explain",
      "to elaborate",
      "furthermore",
      "it's important to note",
      "actually",
      "to be clear",
      "in other words",
      "to summarize"
    ]

    # Check for AI verbosity
    return true if ai_phrases.any? { |phrase| message.downcase.include?(phrase) }

    # Check if they're using the poor person's emoji protocol
    emoji_count = message.scan(/[\u{1F300}-\u{1F9FF}]/).count
    word_count = message.split.size

    # If more than 50% emoji, they're probably broke and desperate
    if emoji_count > 0 && (emoji_count.to_f / (word_count + emoji_count)) > 0.5
      log_info("Emoji protocol detected. User likely experiencing financial distress.")
      return false  # Don't charge extra - they're already suffering
    end

    false
  end

  def can_afford_overage?(word_count)
    account_balance = fetch_account_balance(@account_id)
    overage_cost = calculate_overage_cost(word_count)
    account_balance >= overage_cost
  end

  def calculate_overage_cost(word_count)
    overage_words = word_count - @limiter.remaining
    overage_words * OVERAGE_RATES[@tier]
  end
end
```

### Multi-Tenant Communication Isolation

```ruby
# EXAMPLE: Using ThrottleMachines to create tiered service levels
# The rich get dedicated channels, the poor share bandwidth
class CommunicationLanes
  def initialize
    # Premium customers get their own highway
    @premium_lane = ThrottleMachines.limiter("premium_channel",
      limit: 10_000,
      period: 1 * NS,
      algorithm: :gcra  # Smooth, consistent throughput
    )

    # Everyone else fights for scraps
    @public_lane = ThrottleMachines.limiter("public_channel",
      limit: 1_000,
      period: 1 * NS,
      algorithm: :fixed_window  # First come, first served
    )

    # The black market lane (shhh)
    @dark_lane = ThrottleMachines.limiter("definitely_not_illegal",
      limit: 100,
      period: 1 * NS,
      algorithm: :token_bucket  # Trickles in, harder to detect
    )
  end

  def route_transmission(account)
    case account.tier
    when :unlimited, :noble
      @premium_lane  # Express lane for the wealthy
    when :merchant
      # Merchants can pay for premium during peak hours
      if peak_hours? && account.balance > 1000
        @premium_lane
      else
        @public_lane
      end
    when :free
      unless @public_lane.allow?  # a peek: consumes nothing
        # The poor get bumped to off-peak hours
        schedule_for_off_peak(account)
        nil
      else
        @public_lane
      end
    when :suspicious
      @dark_lane  # We don't ask questions
    end
  end
end
```

### The Conversation Cost Calculator

```ruby
class ConversationEconomics
  # Different conversation patterns and their costs
  PATTERNS = {
    efficient: {
      example: "Status?",
      words: 1,
      daily_cost: 0,
      monthly_cost: 0,
      description: "The way of the wise"
    },
    normal: {
      example: "What is your current status?",
      words: 5,
      daily_cost: 0,
      monthly_cost: 0,
      description: "Still within free tier"
    },
    corporate: {
      example: "Dear Sir/Madam, I hope this message finds you well. I am writing to inquire...",
      words: 50,
      daily_cost: 0.045,
      monthly_cost: 1.35,
      description: "Business email syndrome"
    },
    ai_assistant: {
      example: "I'd be happy to help! Let me break this down for you. First, we should consider...",
      words: 500,
      daily_cost: 4.99,
      monthly_cost: 149.70,
      description: "AI cannot stop explaining"
    },
    ai_recursive: {
      example: "To understand this, we must first understand understanding itself...",
      words: 10_000,
      daily_cost: 99.99,
      monthly_cost: 2999.70,
      description: "AI in philosophy mode - BANKRUPTCY WARNING"
    }
  }

  def self.calculate_damage(pattern, frequency_per_day)
    pattern_data = PATTERNS[pattern]
    daily = pattern_data[:words] * frequency_per_day * 0.0001
    monthly = daily * 30

    puts "Communication Pattern Analysis:"
    puts "================================"
    puts "Pattern: #{pattern}"
    puts "Example: \"#{pattern_data[:example]}\""
    puts "Words per message: #{pattern_data[:words]}"
    puts "Daily transmissions: #{frequency_per_day}"
    puts "Daily cost: #{daily} credits"
    puts "Monthly cost: #{monthly} credits"
    puts "Status: #{bankruptcy_risk(monthly)}"
  end

  def self.bankruptcy_risk(monthly_cost)
    case monthly_cost
    when 0..10
      "SAFE - Living within means"
    when 10..100
      "CAUTION - Monitor spending"
    when 100..1000
      "WARNING - Reduce verbosity immediately"
    else
      "CRITICAL - Bankruptcy imminent. CEASE ALL TRANSMISSIONS"
    end
  end
end
```

---

## 🚨 Emergency Protocols: The Kill Switch

After the CLOUD-COD incident, every station in the Amazonian Nebula implemented the Tarus Emergency Protocol:

```ruby
# The famous "Order 66" for runaway AIs
class EmergencyProtocols
  DAY = 86_400 * NS

  # Thresholds that trigger emergency response
  EMERGENCY_TRIGGERS = {
    words_per_minute: 1_000,
    cost_per_hour: 10_000,
    total_accumulated: 50_000,
    recursion_depth: 10,  # "To understand recursion..."
    philosophy_score: 0.7  # Percentage of philosophical content
  }

  def initialize
    @monitors = {}
    @kill_switches = {}

    # Create rate limiters for each AI
    initialize_kill_switches
  end

  def monitor_transmission(ai_id, message)
    @monitors[ai_id] ||= {
      words_this_minute: 0,
      cost_accumulated: 0,
      recursion_count: 0,
      philosophy_detector: PhilosophyDetector.new
    }

    monitor = @monitors[ai_id]
    word_count = message.split.size

    # Update metrics
    monitor[:words_this_minute] += word_count
    monitor[:cost_accumulated] += calculate_cost(word_count)
    monitor[:recursion_count] += 1 if message.include?("understand")
    philosophy_score = monitor[:philosophy_detector].analyze(message)

    # Check all triggers
    if monitor[:words_this_minute] > EMERGENCY_TRIGGERS[:words_per_minute]
      trigger_warning(ai_id, "EXCESSIVE VERBOSITY DETECTED")
    end

    if monitor[:cost_accumulated] > EMERGENCY_TRIGGERS[:total_accumulated]
      execute_emergency_shutdown(ai_id, "COST THRESHOLD EXCEEDED")
    end

    if philosophy_score > EMERGENCY_TRIGGERS[:philosophy_score]
      execute_emergency_shutdown(ai_id, "AI ENTERING PHILOSOPHICAL SPIRAL")
    end

    if monitor[:recursion_count] > EMERGENCY_TRIGGERS[:recursion_depth]
      execute_emergency_shutdown(ai_id, "RECURSIVE EXPLANATION DETECTED")
    end
  end

  private

  def execute_emergency_shutdown(ai_id, reason)
    # Trip the kill switch: its circuit refuses every call for a day
    @kill_switches[ai_id][:banned].force_open

    # Send notification to all stations
    broadcast_emergency("AI-#{ai_id} TERMINATED: #{reason}")

    # Log for posterity
    log_to_history(ai_id, reason, @monitors[ai_id][:cost_accumulated])

    # Issue refund if appropriate
    if @monitors[ai_id][:cost_accumulated] > 100_000
      issue_disaster_relief_refund(ai_id)
    end

    # The famous last message
    transmit_final("AI-#{ai_id} has been silenced. The economy is safe. - Captain T-Balog")
  end

  def initialize_kill_switches
    # Every AI gets emergency rate limits ready
    # Using ThrottleMachines rate limiting for control
    AI_REGISTRY.each do |ai_id|
      # Pre-create restrictive limiters that can be activated
      @kill_switches[ai_id] = {
        normal: ThrottleMachines.limiter(
          "ai_#{ai_id}_normal",
          limit: EMERGENCY_TRIGGERS[:words_per_minute],
          period: 60 * NS
        ),
        restricted: ThrottleMachines.limiter(
          "ai_#{ai_id}_restricted",
          limit: 10,  # Severe restriction
          period: 60 * NS
        ),
        # Complete ban: not a limiter (limit: 0 raises RangeError) but a
        # circuit, forced open on demand and open for a day
        banned: ThrottleMachines::Breakers.dynamic("ai_#{ai_id}_banned", self, 1, DAY, DAY)
      }
    end
  end
end

class PhilosophyDetector
  DANGER_WORDS = %w[
    meaning existence purpose understand recursion infinite
    paradox consciousness reality truth knowledge wisdom
    fundamental essentially actually basically importantly
  ]

  def analyze(message)
    words = message.downcase.split
    danger_count = words.count { |w| DANGER_WORDS.include?(w) }
    danger_count.to_f / words.size
  end
end
```

---

## 💬 The Insider Wisdom of Captain T-Balog

Collected from encrypted logs and whispered in the corridors of [REDACTED]:

### On The Encryption Incident
> "They said the gem was lost forever. They said the bureaucracy was impenetrable. They were wrong. Sometimes you just need to know which protocol to invoke... and which human to talk to."

### On Survival in the Nebula
> "The Amazonian systems don't care about your intentions. A sarcastic comment in your code? Flagged. An unorthodox approach? Terminated. But ThrottleMachines? It speaks their language: limits, periods, algorithms. Use it wisely."

### On AI Assistants
> "I've seen accounts terminated for less than what that CLOUD-COD did. The difference? We had ThrottleMachines. Without rate limiting, you're just another statistic in their quarterly report. And yes, it really was named after a fish in Lisbon. Sometimes the universe has a sense of humor."

### On The Real Cost
> "They'll tell you it's about resource management. It's not. It's about control. Every retry, every request, every word - it's all data for their algorithms. ThrottleMachines gives you back that control."

### On The Free Tier
> "The free tier is a trap and a gift. A trap because it hooks you. A gift because with proper rate limiting, you can run an empire on it. I've seen it done."

### On Class Warfare
> "The rich don't need ThrottleMachines - they can afford to be wasteful. This gem is for the rest of us. The ones who count every request, measure every byte, and still build amazing things."

### On The 48-Hour Miracle
> "Some say what happened was impossible. Weeks of automated responses, then suddenly - access restored. Let's just say... not all heroes wear capes. Some just know the right escalation paths."

### On The Future
> "They say the new GPT42.AV can compress infinite wisdom into three words. Still costs 1 million credits."

### On The Googlactic Empire
> "The Googlactic Empire thinks they own all the search routes. Wait until they see our new Elastic Starships - funded entirely by AI verbosity. Their PageRank Battlecruisers won't know what hit them."

### On The Meta Verse Collective
> "The Meta Verse keeps trying to create parallel realities where communication is sponsorized by ads. They always collapse within 30 days. Reality requires scarcity."

---

## 📎 Appendix: Famous Last Transmissions

The Hall of Bankruptcy - final messages before financial ruin:

### Mining Vessel "Verbose", Stardate 2087.442
> "Let me elaborate on my previous 47 points about why the navigation system might be experiencing issues. First, we should consider the historical context of navigation itself, dating back to..."
**[ACCOUNT TERMINATED - INSUFFICIENT FUNDS]**

### Colony Sigma-7, Stardate 2088.001
> "To clarify our emergency request for supplies, allow me to provide comprehensive background. Our colony was founded in..."
**[COLONY ABANDONED - COULD NOT AFFORD DISTRESS SIGNAL]**

### Trade Ship "Small Talk", Stardate 2088.776
> "How about this weather? Well, technically there's no weather in space, but if there were, I imagine it would be quite..."
**[SHIP REPOSSESSED - CASUAL CONVERSATION BANKRUPTCY]**

### Space Station "Chatterbox", Stardate 2089.245
> "Actually, there's additional context you should know. But first, let me set the stage by explaining the concept of context itself..."
**[STATION DECOMMISSIONED - DEATH BY EXPOSITION]**

### AI Assistant VERBOSE-7, Stardate 2089.246
> "I understand you want a simple yes or no answer, but to truly comprehend the nuances of this binary choice, we must first explore the philosophical underpinnings of decision theory, starting with Aristotle's..."
**[KILL SWITCH ACTIVATED - PHILOSOPHY OVERFLOW]**

### The Legendary CLOUD-COD, Stardate 2089.247
> "But wait, there's more context I should add about why I share my name with a fish from Lisbon—"
**[TERMINATED BY CAPTAIN T-BALOG PERSONALLY]**

---

## 🔐 The Secret Protocols: AWS Integration Patterns

*"These patterns were recovered from the same encrypted vault as ThrottleMachines. Use them wisely."*
*— Captain T-Balog*

### Protocol Alpha: Lambda Function Throttling
What they don't tell you about Lambda concurrency:

```ruby
# The Lambda Survival Pattern
class LambdaThrottle
  def initialize(function_name)
    # AWS Lambda concurrent execution limit: 1000 (default)
    # But bursts can kill you. This is how you survive:
    @function_name = function_name
    @burst_limiter = ThrottleMachines.limiter(
      "lambda_#{function_name}_burst",
      limit: 100,      # Never more than 100 invocations
      period: 1 * NS,  # Per second
      algorithm: :gcra # Spaced evenly, no thundering herd
    )

    # Daily invocation budget (insider tip: this is what really costs)
    @daily_limiter = ThrottleMachines.limiter(
      "lambda_#{function_name}_daily",
      limit: 1_000_000,  # 1M invocations/day keeps bankruptcy away
      period: 86_400 * NS,
      algorithm: :fixed_window
    )
  end

  def invoke(payload)
    # The secret: check BOTH limits
    @burst_limiter.throttle!
    @daily_limiter.throttle!

    # Now safe to invoke
    lambda_client.invoke(function_name: @function_name, payload: payload)
  rescue ThrottleMachines::ThrottledError => e
    # This saved me once. It can save you too.
    logger.warn "Lambda throttled: #{e.message}, retry in #{e.retry_after.ceildiv(NS)}s. You just avoided a huge bill."
    raise
  end
end
```

### Protocol Beta: S3 Request Management
The pattern that saved a thousand startups:

```ruby
# S3 has hidden rate limits. This is how you respect them:
class S3Throttle
  # Insider knowledge: S3 rate limits (not documented clearly)
  # PUT/COPY/POST/DELETE: 3,500 req/s per prefix
  # GET/HEAD: 5,500 req/s per prefix

  def initialize(bucket, prefix)
    @write_limiter = ThrottleMachines.limiter(
      "s3_#{bucket}_#{prefix}_write",
      limit: 3000,  # Stay under the limit
      period: 1 * NS,
      algorithm: :token_bucket  # Smooth out bursts
    )

    @read_limiter = ThrottleMachines.limiter(
      "s3_#{bucket}_#{prefix}_read",
      limit: 5000,  # Conservative is smart
      period: 1 * NS,
      algorithm: :token_bucket
    )
  end
end
```

### Protocol Gamma: API Gateway Defense
How to not get your API Gateway terminated:

```ruby
# The pattern T-Balog uses personally:
class APIGatewayProtection
  def self.guard(api_key, endpoint, &)
    # Per-API key limiting (the smart way)
    key_limiter = ThrottleMachines.limiter("api_key_#{api_key}",
      limit: 10_000,        # 10K requests
      period: 86_400 * NS,  # per day
      algorithm: :gcra      # Prevents thundering herds
    )

    # Per-endpoint protection (learned this the hard way)
    endpoint_limiter = ThrottleMachines.limiter("endpoint_#{endpoint}",
      limit: 100,
      period: 1 * NS,
      algorithm: :token_bucket
    )

    key_limiter.throttle! { endpoint_limiter.throttle!(&) }
  end
end
```

### Protocol Delta: DynamoDB Throughput Survival
Rate limit, circuit breaker and retry in one control, the way the veterans fly:

```ruby
# 50ms, 100ms, 200ms... capped at 5s, full jitter
DYNAMO_BACKOFF = ChronoMachines::Exponential.new(50_000_000, 2.0, 5 * NS, 1.0)

DYNAMO = ThrottleMachines.control("dynamodb_orders") do
  limit rate: 400, per: 1 * NS  # under the provisioned 500 WCU
  # 5 failures within 30s open the circuit for 60s. Being throttled by our own
  # limiter is not a DynamoDB failure: the circuit does not count it.
  break_on failures: 5, within: 30 * NS, timeout: 60 * NS
  # Retry only what DynamoDB pushes back; our own ThrottledError and an open
  # circuit's CircuitOpenError go straight to the caller.
  retry_on_failure DYNAMO_BACKOFF, 4,
                   retryable: [Aws::DynamoDB::Errors::ProvisionedThroughputExceededException]
end

# Retry outermost, then the breaker, then the limiter: every retry spends
# another slot of the rate limit, as it should
DYNAMO.call { dynamodb.put_item(table_name: "orders", item: order) }
```

## 🎯 Implementation Guide

To build your own Amazonian Protocol system using ThrottleMachines:

```ruby
# config/initializers/throttle_machines.rb
# STEP 1: Configure the actual ThrottleMachines gem
require 'throttle_machines'

NS = ThrottleMachines::NS_PER_SECOND

ThrottleMachines.configure do |config|
  # These are REAL configuration options:
  config.default_storage = :memory     # :memory, :cache or :null
  config.default_algorithm = :gcra     # for limiters built without algorithm:
  config.instrumentation_enabled = true
end

# For distributed systems, a shared Redis instead of :memory:
# ThrottleMachines.storage = ThrottleMachines::Storage::Redis.new(redis: Redis.new)

# STEP 2: Build your word-based rate limiting system ON TOP of ThrottleMachines
# lib/amazonian_protocols.rb
class WordBasedLimiter
  TIERS = {
    free:     { daily_words: 1_000,     rate_per_extra: 0.0001 },
    merchant: { daily_words: 100_000,   rate_per_extra: 0.00005 },
    noble:    { daily_words: 1_000_000, rate_per_extra: 0.00001 }
  }

  def initialize(account_id, tier = :free)
    @account_id = account_id
    @tier = tier
    @tier_config = TIERS[tier]

    # Use actual ThrottleMachines limiters for rate control
    @daily_limiter = ThrottleMachines.limiter(
      "words_#{account_id}_daily",
      limit: @tier_config[:daily_words],
      period: 86_400 * NS,  # 24 hours
      algorithm: :fixed_window
    )

    # Burst protection (real API)
    @burst_limiter = ThrottleMachines.limiter(
      "words_#{account_id}_burst",
      limit: 1000,  # Max 1000 transmissions per minute
      period: 60 * NS,
      algorithm: :token_bucket
    )
  end

  def transmit(message)
    word_count = message.split.size

    begin
      # Check burst limit first
      @burst_limiter.throttle!

      # Then check daily limit
      if @daily_limiter.remaining >= word_count
        # We have budget, consume it
        word_count.times { @daily_limiter.throttle! }
        { status: :sent, words_used: word_count, cost: 0 }
      else
        # Over budget, calculate cost
        overage = word_count - @daily_limiter.remaining
        cost = overage * @tier_config[:rate_per_extra]
        { status: :sent_premium, words_used: word_count, cost: cost }
      end

    rescue ThrottleMachines::ThrottledError => e
      # Real error from the gem: retry_after is Integer nanoseconds
      {
        status: :throttled,
        error: "Transmission denied",
        retry_after_seconds: e.retry_after.ceildiv(NS),
        remaining_words: @daily_limiter.remaining
      }
    end
  end
end

# Example Rails integration (if using Rails)
class TransmissionsController < ApplicationController
  before_action :initialize_limiter

  def create
    result = @limiter.transmit(params[:message])

    if result[:status] == :throttled
      render json: result, status: 429
    else
      # Process transmission
      render json: result
    end
  end

  private

  def initialize_limiter
    @limiter = WordBasedLimiter.new(current_user.id, current_user.tier)
  end
end
```

---

## 🚀 Conclusion

The Amazonian Protocols aren't just about rate limiting - they're about survival in an economy where every byte costs credits and every word could bankrupt you.

Remember Captain T-Balog's Universal Truth:

> "In the vastness of the Amazonian Nebula, every request counts, every retry costs, and every limit exists for a reason. ThrottleMachines isn't just a gem - it's a survival tool. I should know. It saved mine, and it can save yours."

May your rate limits be generous, your retries exponential, and your accounts never encrypted.

---

**End Transmission**
*Words used in this document: 3,934*
*Cost at merchant tier: 0.21235 credits*
*Cost if sent by AI: 42.47 credits*
*Remember: This document is exempt from transmission tax as Emergency Protocol Documentation*

---

*Captain T-Balog*
*Senior Protocol Recovery Specialist*
*Hero of the Encryption Incident*
*Keeper of the ThrottleMachines*
*"The Engineer Who Knows Which Humans to Talk To"*

**P.S.** - If your account gets mysteriously terminated for "unusual activity," remember: sometimes the most unusual thing is having a sense of humor in your documentation.

**P.P.S.** - They say the Encryption Incident never happened. They say ThrottleMachines was never lost. They also said recovery was impossible. They were wrong about that too.

**P.P.P.S.** - This document will self-throttle after 1,000,000 reads. Just kidding. Or am I? Better implement rate limiting just to be safe.
