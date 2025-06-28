# frozen_string_literal: true

require 'ipaddr'

module ThrottleMachines
  class RackMiddleware
    class Configuration
      DEFAULT_BLOCKLISTED_RESPONDER = ->(_req) { [403, { 'content-type' => 'text/plain' }, ["Forbidden\n"]] }

      DEFAULT_THROTTLED_RESPONDER = lambda do |req|
        match_data = req.env['rack.attack.match_data']
        retry_after = match_data[:retry_after] || 60

        [429, { 'content-type' => 'text/plain', 'retry-after' => retry_after.to_s }, ["Retry later\n"]]
      end

      attr_reader :throttles, :tracks, :safelists, :blocklists
      attr_accessor :throttled_responder, :blocklisted_responder

      def initialize
        @throttles = {}
        @tracks = {}
        @safelists = {}
        @blocklists = {}
        @anonymous_safelists = []
        @anonymous_blocklists = []
        @fail2bans = {}
        @allow2bans = {}

        @throttled_responder = DEFAULT_THROTTLED_RESPONDER
        @blocklisted_responder = DEFAULT_BLOCKLISTED_RESPONDER
      end

      # DSL Methods
      def throttle(name, options = {}, &)
        @throttles[name] = Throttle.new(name, options, &)
      end

      def track(name, options = {}, &)
        @tracks[name] = Track.new(name, options, &)
      end

      def safelist(name = nil, &)
        if name
          @safelists[name] = Safelist.new(name, &)
        else
          @anonymous_safelists << Safelist.new(nil, &)
        end
      end

      def blocklist(name = nil, &)
        if name
          @blocklists[name] = Blocklist.new(name, &)
        else
          @anonymous_blocklists << Blocklist.new(nil, &)
        end
      end

      def safelist_ip(ip_address)
        @anonymous_safelists << Safelist.new(nil) { |req| req.ip == ip_address }
      end

      def blocklist_ip(ip_address)
        @anonymous_blocklists << Blocklist.new(nil) { |req| req.ip == ip_address }
      end

      def fail2ban(name, options = {}, &)
        @fail2bans[name] = Fail2Ban.new(name, options, &)
      end

      def allow2ban(name, options = {}, &)
        @allow2bans[name] = Allow2Ban.new(name, options, &)
      end

      # Check methods
      def safelisted?(request)
        @anonymous_safelists.any? { |safelist| safelist.matched_by?(request) } ||
          @safelists.values.any? { |safelist| safelist.matched_by?(request) }
      end

      def blocklisted?(request)
        # Check explicit blocklists
        return true if @anonymous_blocklists.any? { |blocklist| blocklist.matched_by?(request) }
        return true if @blocklists.values.any? { |blocklist| blocklist.matched_by?(request) }

        # Check fail2bans
        @fail2bans.values.any? { |fail2ban| fail2ban.banned?(request) }
      end

      def throttled?(request)
        # Process allow2bans first (they can reset fail2ban counters)
        @allow2bans.each_value { |allow2ban| allow2ban.matched_by?(request) }

        # Check throttles
        @throttles.values.any? { |throttle| throttle.matched_by?(request) }
      end

      def tracked?(request)
        @tracks.each_value { |track| track.matched_by?(request) }
      end
    end
  end
end
