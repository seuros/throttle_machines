local state = redis.call('HGET', KEYS[1], 'state') or 'closed'
local now = ARGV[3]
local timeout = tonumber(ARGV[2])

if state == 'half_open' then
  -- Failure in half-open state, just re-open the circuit
  redis.call('HMSET', KEYS[1],
    'state', 'open',
    'opens_at', tonumber(now) + timeout,
    'last_failure', now
  )
else -- state is 'closed' or nil
  local failures = redis.call('HINCRBY', KEYS[1], 'failures', 1)
  redis.call('HSET', KEYS[1], 'last_failure', now)
  
  if failures >= tonumber(ARGV[1]) then
    redis.call('HMSET', KEYS[1],
      'state', 'open',
      'opens_at', tonumber(now) + timeout
    )
  end
end

redis.call('EXPIRE', KEYS[1], timeout * 2)