-- A stand-in for the Redis a script runs in: its keyspace, its TIME and its
-- argument and reply conversions, driven line by line over stdin. Run it
-- under LuaJIT, whose numbers are doubles like those of Redis's Lua 5.1.
--
--   TIME <seconds> <microseconds>       what TIME answers from now on
--   LOAD <name> <path>                  compile a script under a name
--   EVAL <name> <nkeys> <keys...> <argv...>
--   GET <key>
--   DEL <keys...>
--
-- Every command answers one line: tab-separated values tagged i (integer),
-- s (string) or n (nil), led by a * field when a script answers a table;
-- "ok", or "E<TAB>message" when the script raised.
local WRONGTYPE = 'WRONGTYPE Operation against a key holding the wrong kind of value'
local data = {}
local expires = {} -- key -> instant in whole milliseconds of TIME
local time = { '0', '0' }
local scripts = {}

local function now_ms()
  return tonumber(time[1]) * 1000 + math.floor(tonumber(time[2]) / 1000)
end

-- A key past its expiry is gone, as Redis evicts it on access.
local function live(key)
  if expires[key] ~= nil and expires[key] <= now_ms() then
    data[key], expires[key] = nil, nil
  end
  return data[key]
end

-- Redis passes a Lua number to a command as "%.17g".
local function argument(value)
  if type(value) == 'number' then return string.format('%.17g', value) end
  return tostring(value)
end

local function hash(key)
  local value = live(key)
  if value ~= nil and type(value) ~= 'table' then error(WRONGTYPE) end
  return value
end

redis = {}

function redis.call(command, ...)
  local args = { ... }
  command = string.upper(command)
  if command == 'TIME' then
    return { time[1], time[2] }
  elseif command == 'GET' then
    if type(live(args[1])) == 'table' then error(WRONGTYPE) end
    return data[args[1]] or false
  elseif command == 'SET' then
    data[args[1]], expires[args[1]] = argument(args[2]), nil
    return { ok = 'OK' }
  elseif command == 'INCRBY' then
    local value = live(args[1])
    if type(value) == 'table' then error(WRONGTYPE) end
    local count = (tonumber(value) or 0) + tonumber(args[2])
    data[args[1]] = string.format('%d', count)
    return count
  elseif command == 'PTTL' then
    if live(args[1]) == nil then return -2 end
    if expires[args[1]] == nil then return -1 end
    return expires[args[1]] - now_ms()
  elseif command == 'HMGET' then
    local h = hash(args[1])
    local out = {}
    for i = 2, #args do out[i - 1] = (h and h[args[i]]) or false end
    return out
  elseif command == 'HSET' then
    local h = hash(args[1]) or {}
    for i = 2, #args, 2 do h[args[i]] = argument(args[i + 1]) end
    data[args[1]] = h
    return (#args - 1) / 2
  elseif command == 'PEXPIRE' then
    if live(args[1]) == nil then return 0 end
    expires[args[1]] = now_ms() + tonumber(args[2])
    return 1
  end
  error('the shim has no ' .. command)
end

-- Redis turns a Lua number reply into an integer by truncation. A table
-- reply leads with a `*` field, as RESP marks an array.
local function encode(reply)
  local out = {}
  if type(reply) == 'table' then
    out[1] = '*'
  else
    reply = { reply }
  end
  for i = 1, #reply do
    local value = reply[i]
    if type(value) == 'number' then
      out[#out + 1] = 'i' .. string.format('%d', value >= 0 and math.floor(value) or math.ceil(value))
    elseif value == false or value == nil then
      out[#out + 1] = 'n'
    else
      out[#out + 1] = 's' .. tostring(value)
    end
  end
  return table.concat(out, '\t')
end

local function split(line)
  local fields = {}
  for field in string.gmatch(line, '[^\t]+') do fields[#fields + 1] = field end
  return fields
end

for line in io.lines() do
  local f = split(line)
  if f[1] == 'TIME' then
    time = { f[2], f[3] }
    print('ok')
  elseif f[1] == 'LOAD' then
    scripts[f[2]] = assert(loadfile(f[3]))
    print('ok')
  elseif f[1] == 'GET' then
    local value = live(f[2])
    print(value == nil and 'n' or ('s' .. tostring(value)))
  elseif f[1] == 'DEL' then
    local n = 0
    for i = 2, #f do
      if live(f[i]) ~= nil then n = n + 1 end
      data[f[i]], expires[f[i]] = nil, nil
    end
    print('i' .. n)
  elseif f[1] == 'EVAL' then
    local nkeys = tonumber(f[3])
    KEYS, ARGV = {}, {}
    for i = 1, nkeys do KEYS[i] = f[3 + i] end
    for i = 4 + nkeys, #f do ARGV[#ARGV + 1] = f[i] end
    local ok, reply = pcall(scripts[f[2]])
    if ok then print(encode(reply)) else print('E\t' .. tostring(reply)) end
  end
  io.stdout:flush()
end
