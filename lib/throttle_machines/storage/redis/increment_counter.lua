-- ARGV: amount, window (ms).
local count = redis.call('INCRBY', KEYS[1], ARGV[1])

-- Set expiry if the key is new or has none.
if redis.call('PTTL', KEYS[1]) < 0 then
  redis.call('PEXPIRE', KEYS[1], ARGV[2])
end

return count
