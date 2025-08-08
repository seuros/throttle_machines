local state = redis.call('HGET', KEYS[1], 'state')

if state == 'half_open' then
  -- Increment half-open attempts and potentially close the circuit
  local attempts = redis.call('HINCRBY', KEYS[1], 'half_open_attempts', 1)
  
  if attempts >= tonumber(ARGV[1]) then
    redis.call('DEL', KEYS[1])
  end
elseif state == 'closed' then
  -- Reset failure count on success in closed state
  local failures = redis.call('HGET', KEYS[1], 'failures')
  if failures and tonumber(failures) > 0 then
    redis.call('HSET', KEYS[1], 'failures', 0)
  end
end