local data = redis.call('HGETALL', KEYS[1])
if #data == 0 then
  return {}
end

local state = {}
for i = 1, #data, 2 do
  state[data[i]] = data[i + 1]
end

-- Auto-transition from open to half-open if timeout passed
if state['state'] == 'open' and state['opens_at'] then
  local now = tonumber(ARGV[1])
  local opens_at = tonumber(state['opens_at'])
  
  if now >= opens_at then
    redis.call('HSET', KEYS[1], 'state', 'half_open', 'half_open_attempts', '0')
    state['state'] = 'half_open'
    state['half_open_attempts'] = '0'
  end
end

return state