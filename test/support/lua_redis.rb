# frozen_string_literal: true

require 'digest/sha1'
require 'redis'
require 'tempfile'

module ThrottleMachines
  # A Redis client over test/support/redis_shim.lua run by LuaJIT: the Lua
  # scripts run for real, with doubles for numbers as in Redis, and TIME
  # answers whatever `time` (Integer nanoseconds) reads, truncated to
  # microseconds as Redis answers it, and keys expire by it. Enough of a
  # client for Storage::Redis's GCRA, token bucket and fixed window checks.
  class LuaRedis
    SHIM = File.expand_path('redis_shim.lua', __dir__)
    LUAJIT = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { File.join(it, 'luajit') }
                .find { File.executable?(it) }

    def self.available? = !LUAJIT.nil?

    def initialize(time:)
      @time = time
      @io = IO.popen([LUAJIT, SHIM], 'r+')
      @loaded = {}
      @sources = []
    end

    def ping = 'PONG'

    def evalsha(sha, keys:, argv:)
      raise ::Redis::CommandError, 'NOSCRIPT No matching script. Please use EVAL.' unless @loaded[sha]

      run(sha, keys, argv)
    end

    def eval(script, keys:, argv:)
      sha = Digest::SHA1.hexdigest(script)
      load_script(sha, script) unless @loaded[sha]
      run(sha, keys, argv)
    end

    # Keys expire by `time`, so GET first sets TIME as a script call does.
    def get(key)
      clock
      command('GET', key).first
    end

    def del(*keys) = command('DEL', *keys).first

    def close
      @io.close
      @sources.each(&:close!)
    end

    private

    def load_script(sha, script)
      source = Tempfile.new(%w[script .lua])
      source.write(script)
      source.flush
      @sources << source
      command('LOAD', sha, source.path)
      @loaded[sha] = true
    end

    # A table reply is an Array, anything else the bare value, as redis-rb
    # answers them.
    def run(sha, keys, argv)
      clock
      reply = command('EVAL', sha, keys.size, *keys, *argv)
      reply.first == :array ? reply.drop(1) : reply.first
    end

    def clock
      seconds, nanoseconds = @time.call.divmod(NS_PER_SECOND)
      command('TIME', seconds, nanoseconds / 1000)
    end

    def command(*fields)
      @io.puts(fields.join("\t"))
      reply = @io.gets.chomp
      raise ::Redis::CommandError, reply.delete_prefix("E\t") if reply.start_with?("E\t")
      return [] if reply == 'ok'

      reply.split("\t").map do |value|
        case value[0]
        when '*' then :array
        when 'i' then Integer(value[1..])
        when 's' then value[1..]
        end
      end
    end
  end
end
