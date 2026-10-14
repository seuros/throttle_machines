local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local refill_rate = tonumber(ARGV[2])
local ttl = tonumber(ARGV[3])
local now = tonumber(ARGV[4])

local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
local tokens = tonumber(bucket[1]) or capacity
local last_refill = tonumber(bucket[2]) or now

-- Refill tokens
local elapsed = now - last_refill
local tokens_to_add = elapsed * refill_rate
tokens = math.min(tokens + tokens_to_add, capacity)

-- `elapsed` carries the clock's rounding; a token due exactly now may come
-- out a hair short of 1. The slack scales with the clock, as in the native core.
local slack = 2.220446049250313e-16 * 64 * math.max(math.abs(now), 1) * refill_rate
local allow = tokens >= 1 - slack
if allow then
  tokens = math.max(tokens - 1, 0)
  redis.call('HMSET', key, 'tokens', tokens, 'last_refill', now)
  redis.call('EXPIRE', key, ttl)
end

-- Redis truncates Lua numbers in replies to integers; send the count as text.
return { allow and 1 or 0, string.format('%.17g', tokens) }
