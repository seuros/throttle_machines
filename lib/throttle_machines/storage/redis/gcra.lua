-- GCRA admission, the native core's arithmetic in Integer nanoseconds.
-- `now` is the server's TIME, one clock for every client. The theoretical
-- arrival time is stored relative to `epoch`, a TIME second, and rebased to
-- the current second on every write, so every number stays small enough to
-- be exact in Lua's doubles.
-- ARGV: emission_interval, delay_tolerance, ttl (ms).
-- Reply: {1, calls still admitted} or {0, 0} (throttled, nothing stored).
local key = KEYS[1]
local interval = tonumber(ARGV[1])
local tolerance = tonumber(ARGV[2])
local ttl = tonumber(ARGV[3])

local time = redis.call('TIME')
local second = tonumber(time[1])
local state = redis.call('HMGET', key, 'tat', 'epoch')
local shift = (second - (tonumber(state[2]) or second)) * 1000000000
local now = shift + tonumber(time[2]) * 1000

local tat = tonumber(state[1]) or 0
local ahead = math.max(tat - now, 0)
if ahead > tolerance then
  return { 0, 0 }
end

redis.call('HSET', key, 'tat', string.format('%.0f', math.max(tat, now) + interval - shift), 'epoch', second)
redis.call('PEXPIRE', key, ttl)
return { 1, math.floor((tolerance - ahead) / interval) }
