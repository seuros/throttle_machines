-- Token bucket admission, the native core's arithmetic in Integer
-- nanoseconds. `now` is the server's TIME, one clock for every client. The
-- refill instant is stored relative to `epoch`, a TIME second, and rebased
-- to the current second on every write, so every number stays small enough
-- to be exact in Lua's doubles.
-- ARGV: capacity, refill_every, ttl (ms).
-- Reply: {1, tokens left} or {0, 0} (throttled, nothing stored).
local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local refill = tonumber(ARGV[2])
local ttl = tonumber(ARGV[3])

local time = redis.call('TIME')
local second = tonumber(time[1])
local bucket = redis.call('HMGET', key, 'tokens', 'refilled_at', 'epoch')
local shift = (second - (tonumber(bucket[3]) or second)) * 1000000000
local now = shift + tonumber(time[2]) * 1000

local tokens = math.min(tonumber(bucket[1]) or capacity, capacity)
local refilled_at = tonumber(bucket[2]) or 0

-- A partial span toward the next token is kept; nothing is banked past capacity.
local earned = math.floor(math.max(now - refilled_at, 0) / refill)
if tokens + earned >= capacity then
  tokens = capacity
  refilled_at = math.max(refilled_at, now)
else
  tokens = tokens + earned
  refilled_at = refilled_at + earned * refill
end

if tokens < 1 then
  return { 0, 0 }
end

tokens = tokens - 1
redis.call('HSET', key, 'tokens', tokens, 'refilled_at', string.format('%.0f', refilled_at - shift), 'epoch', second)
redis.call('PEXPIRE', key, ttl)
return { 1, tokens }
