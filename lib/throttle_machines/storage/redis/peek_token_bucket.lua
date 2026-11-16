-- Token bucket peek, the native core's arithmetic in Integer nanoseconds,
-- on the server's TIME (see token_bucket.lua for how instants are stored).
-- ARGV: capacity, refill_every.
-- Reply: {1, tokens available, 0} or {0, 0, nanoseconds until one is}.
local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local refill = tonumber(ARGV[2])

local time = redis.call('TIME')
local second = tonumber(time[1])
local bucket = redis.call('HMGET', key, 'tokens', 'refilled_at', 'epoch')
local now = (second - (tonumber(bucket[3]) or second)) * 1000000000 + tonumber(time[2]) * 1000

local tokens = math.min(tonumber(bucket[1]) or capacity, capacity)
local refilled_at = tonumber(bucket[2]) or 0

local earned = math.floor(math.max(now - refilled_at, 0) / refill)
if tokens + earned >= capacity then
  return { 1, capacity, 0 }
end

tokens = tokens + earned
if tokens >= 1 then
  return { 1, tokens, 0 }
end

refilled_at = refilled_at + earned * refill
return { 0, 0, string.format('%.0f', math.max(refilled_at + refill - now, 0)) }
