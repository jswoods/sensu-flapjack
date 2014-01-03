require 'json'
require 'rubygems'
require 'sensu/redis'


module Sensu::Extension
  class Flapjack < Handler
    def name
      'flapjack'
    end

    def description
      'outputs events to the flapjack redis database'
    end

    def post_init
      @redis = Sensu::Redis.connect({
        :host => @settings[:flapjack]["host"] || '127.0.0.1',
        :port => @settings[:flapjack]["port"] || 6379,
        :channel => @settings[:flapjack]["channel"] || 'events',
        :database => @settings[:flapjack]["db"] || 0,
      })
      # For now we want sensu to start even if the flapjack redis instance
      # is not available.
      @redis.on_error do |error|
        @logger.warn("Flapjack redis instance not available on #{@settings[:flapjack]["host"]}")
      end
    end

    def run(event)
      event = Oj.load(event)#[:check][:output]
      state = event[:check][:status] 
      if state == 0
        check_state = "ok"
      elsif state == 2
        check_state = "critical"
      else
        check_state = "unknown"
      end
      timestamp = event[:check][:issued]
      entity = event[:client][:name] 
      check = event[:check][:name] 
      check_output = event[:check][:output] 
      details = '' 

      begin
        check_output = JSON.parse(check_output)
        check_output_parsed = ''
        check_output.each do |line|
          check_output_parsed << "#{line['name']}=#{line['value']} "
        end
        check_output = check_output_parsed
      rescue
        check_output_parsed = check_output
      end

      event = {
        'entity'    => entity,
        'check'     => check,
        'type'      => 'service',
        'state'     => check_state,
        'summary'   => check_output_parsed,
        'details'   => details,
        'time'      => timestamp,
      }

      @redis.lpush('events', event.to_json)

      yield("sent flapjack event", 0)
    end
  end
end
