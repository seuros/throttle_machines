local key = KEYS[1]
local emission_interval = tonumber(ARGV[1])
local delay_tolerance = tonumber(ARGV[2])
local now = tonumber(ARGV[3])

local tat = redis.call('GET', key)
if not tat then
  tat = 0
else
  tat = tonumber(tat)
end

tat = math.max(tat, now)
-- The TAT is a running sum of emission intervals, so an on-schedule arrival
-- can overshoot the tolerance by a few ulps; the slack scales with the clock.
local slack = 2.220446049250313e-16 * 64 * math.max(math.abs(tat), 1)
local allow = (tat - now) <= delay_tolerance + slack

-- Redis truncates Lua numbers in replies to integers; send the TAT as text.
return { allow and 1 or 0, string.format('%.17g', tat) }
