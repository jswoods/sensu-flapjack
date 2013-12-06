#!/opt/sensu/embedded/bin/ruby

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-handler'
require 'timeout'
require 'redis'
require 'oj'
Oj.default_options = { :indent => 0, :mode => :strict }

require 'dante'

require 'flapjack/configuration'
require 'flapjack/data/event'

FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'production'

class SendToFlapjack < Sensu::Handler
  def short_name
    @event['client']['name'] + '/' + @event['check']['name']
  end

  def action_to_string
   @event['action'].eql?('resolve') ? "RESOLVED" : "ALERT"
  end

  def handle
    config = Flapjack::Configuration.new
    config.load('/etc/flapjack/config.yaml')
    config_env = config.all

    if config_env.nil? || config_env.empty?
      puts "No config data for environment '#{FLAPJACK_ENV}' found in '#{options.config}'"
      puts optparse
      exit 1
    end

    redis_options = config.for_redis
    redis = Redis.new(redis_options)

    object_type = 'SERVICEPERFDATA'
    timestamp = @event['check']['issued']
    entity = @event['client']['name'] 
    check = @event['check']['name'] 
    state = @event['check']['status'] 
    check_output = @event['check']['output'] 
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

    if state == 0
      check_state = "ok"
    elsif state == 2
      check_state = "critical"
    else
      check_state = "unknown"
    end

    begin
      event = {
        'entity'    => entity,
        'check'     => check,
        'type'      => 'service',
        'state'     => check_state,
        'summary'   => check_output_parsed,
        'details'   => details,
        'time'      => timestamp,
      }

      Flapjack::Data::Event.add(event, :redis => redis)
    rescue Redis::CannotConnectError
      puts "Error, unable to to connect to the redis server (#{$!})"
    end
  end
end
