-- GCRA peek, the native core's arithmetic in Integer nanoseconds, on the
-- server's TIME (see gcra.lua for how instants are stored).
-- ARGV: emission_interval, delay_tolerance.
-- Reply: {1, calls admitted now, 0} or {0, 0, nanoseconds until admitted}.
local key = KEYS[1]
local interval = tonumber(ARGV[1])
local tolerance = tonumber(ARGV[2])

local time = redis.call('TIME')
local second = tonumber(time[1])
local state = redis.call('HMGET', key, 'tat', 'epoch')
local now = (second - (tonumber(state[2]) or second)) * 1000000000 + tonumber(time[2]) * 1000

local tat = tonumber(state[1]) or 0
local ahead = math.max(tat - now, 0)
if ahead > tolerance then
  return { 0, 0, string.format('%.0f', ahead - tolerance) }
end

return { 1, math.floor((tolerance + interval - ahead) / interval), 0 }
