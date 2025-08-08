local count = redis.call('INCRBY', KEYS[1], ARGV[1])
local ttl = redis.call('TTL', KEYS[1])

-- Set expiry if key is new (ttl == -2) or has no TTL (ttl == -1)
if ttl <= 0 then
  redis.call('EXPIRE', KEYS[1], ARGV[2])
end

return count