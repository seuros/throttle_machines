local key = KEYS[1]
local emission_interval = tonumber(ARGV[1])
local delay_tolerance = tonumber(ARGV[2])
local ttl = tonumber(ARGV[3])
local now = tonumber(ARGV[4])

local tat = redis.call('GET', key)
if not tat then
  tat = 0
else
  tat = tonumber(tat)
end

tat = math.max(tat, now)
local allow = (tat - now) <= delay_tolerance

if allow then
  local new_tat = tat + emission_interval
  redis.call('SET', key, new_tat, 'EX', ttl)
end

return { allow and 1 or 0, tat }