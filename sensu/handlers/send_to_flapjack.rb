#!/opt/sensu/embedded/bin/ruby

require 'json'
require 'redis'
require 'flapjack/configuration'
require 'flapjack/data/event'

FLAPJACK_ENV = ENV['FLAPJACK_ENV'] || 'production'

input_event = JSON.parse(STDIN.read, :symbolize_names => true)

config = Flapjack::Configuration.new
config.load('/etc/flapjack/flapjack_config.yaml')
config_env = config.all

if config_env.nil? || config_env.empty?
  puts "No config data for environment '#{FLAPJACK_ENV}' found in '#{options.config}'"
  puts optparse
  exit 1
end

redis_options = config.for_redis
redis = Redis.new(redis_options)

timestamp = input_event[:check][:issued]
entity = input_event[:client][:name] 
check = input_event[:check][:name] 
state = input_event[:check][:status] 
check_output = input_event[:check][:output] 
details = '' 

# Make metrics somewhat human-readable
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
