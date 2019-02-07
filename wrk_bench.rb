#!/usr/bin/env ruby

require_relative "bench_lib"
include BenchLib

require "optparse"
require "date"
require "json"

OPTS = {
  warmup_seconds: 5,
  benchmark_seconds: 180,
  port: 4323,
  concurrency: 1,
  wrk_binary: "wrk",
  wrk_connections: 100,
  url: "http://127.0.0.1:PORT/simple_bench/static",
  server_pre_cmd: "bundle install && bundle exec rake db:migrate",
  server_cmd: "rackup -p PORT",
  server_kill_matcher: "rackup",
  server_kill_command: nil,
  script_location: "./final_report.lua"
  out_file: "rsb_output_TIME.json",
  timestamp: Time.now.to_i,
  verbose: 1,
}

leftover_args = OptionParser.new do |opts|
  opts.banner = <<BANNER
Usage: ruby wrk_bench.rb [options]

The first instance of the following strings will be replaced automatically if present
in URLs, output files or commands:

  PORT: the port number for the benchmark server
  TIMESTAMP: the number of integer seconds since Jan 1st, 1970 GMT that the benchmark runs

Defaults:

#{OPTS.map { |key, val| "#{key}: #{val}" }.join("\n")}

Specific options:
BANNER
  opts.on("-w NUMBER", "--warmup-seconds NUMBER", Integer, "seconds' worth of warmup iterations") do |n|
    OPTS[:warmup_seconds] = n.to_i
  end
  opts.on("-n NUMBER", "--num-iterations NUMBER", Integer, "seconds' worth of benchmarked iterations") do |n|
    OPTS[:benchmark_seconds] = n
  end
  opts.on("-c NUMBER", "--ab-concurrency NUMBER", Integer, "number of concurrent wrk threads") do |n|
    OPTS[:concurrency] = n
  end
  opts.on("--wrk-connections NUMBER", Integer, "number of open wrk TCP connections") do |n|
    OPTS[:wrk_connections] = n
  end
  opts.on("-u URL", "--url URL", "The URL to benchmark") do |u|
    OPTS[:url] = u
  end
  opts.on("-p NUMBER", "--port NUMBER", Integer, "port number for Rails server") do |p|
    OPTS[:port] = p
  end
  opts.on("--wrk-path PATH", "path to binary for wg/wrk benchmarking program") do |p|
    OPTS[:wrk_binary] = p
  end
  opts.on("--script-location PATH", "Path to reporting Lua script") do |p|
    OPTS[:script_location] = p
  end
  opts.on("--server-command CMD", "Command to run server (and check process list for running server)") do |sc|
    OPTS[:server_cmd] = sc
  end
  opts.on("--server-pre-command CMD", "Command to run before starting server") do |spc|
    OPTS[:server_pre_cmd] = spc
  end
  opts.on("--server-kill-match CMD", "String to match when killing processes") do |skm|
    OPTS[:server_kill_matcher] = skm
    OPTS[:server_kill_command] = nil
  end
  opts.on("--server-kill-command CMD", "String to match when killing processes") do |skc|
    OPTS[:server_kill_command] = skc
    OPTS[:server_kill_matcher] = nil
  end
  opts.on("-o STRING", "--output STRING", "output filename") do |p|
    OPTS[:out_file] = p
  end
  opts.on("-v VAL", "--verbose VAL", "Verbose setting, 0 or higher") do |v|
    if v == "0"
      OPTS[:verbose] = false
    elsif v.to_i > 0
      OPTS[:verbose] = v.to_i
    else
      raise "Unrecognized verbosity value: #{v.inspect}! Use an integer 0 or higher."
    end
  end
  opts.on("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse(ARGV)

if leftover_args != []
    raise "Illegal or unexpected extra arguments: #{leftover_args.inspect}"
end

if OPTS[:wrk_binary] == "wrk"
    which_wrk = `which wrk`
    unless which_wrk && which_wrk.strip != ""
        raise "No wg/wrk binary in path! Build or install the binary and/or specify a path with --wrk-path!"
    end
end

# In some options, there's a text substitution for variables like PORT and TIMESTAMP
[:url, :server_cmd, :server_pre_cmd, :server_kill_matcher, :server_kill_command, :out_file].each do |opt|
  next if OPTS[opt].nil?
  OPTS[opt].gsub! "PORT", OPTS[:port].to_s
  OPTS[opt].gsub! "TIMESTAMP", OPTS[:timestamp].to_s
end

env_vars = ENV.keys
important_env_vars = ["LD_PRELOAD"] + env_vars.select { |name| name.downcase["ruby"] || name.downcase["gem"] || name.downcase["rsb"] }
env_hash = {}
important_env_vars.each { |var| env_hash["env-#{var}"] = ENV[var] }
env_hash["wrk_path"] = `which wrk`

# Information about the host we're running on
output = {
    "version" => 1, # version of output format
    "settings" => OPTS,  # command-line and environmental settings for this script
    "environment" => system_environment.merge(env_hash),
    "requests" => {
      "warmup" => [],
      "benchmark" => [],
      #"benchmark_min_starttime"
      #"benchmark_max_starttime"
    }
}

server_env = ServerEnvironment.new OPTS[:server_cmd],
                                   server_pre_cmd: OPTS[:server_pre_cmd],
                                   server_kill_substring: OPTS[:server_kill_matcher],
                                   server_kill_command: OPTS[:server_kill_command],
                                   self_name: "wrk_bench",
                                   url: OPTS[:url]

def verbose(str)
  puts str if OPTS[:verbose] > 0
end

if OPTS[:server_kill_matcher]
  server_env.server_cleanup # make sure the server isn't running already - *if* we can check easily without running a kill command
end

raise "URL #{OPTS[:url].inspect} should not be available before the server runs!" if server_env.url_available?

server_env.with_url_available do
  verbose "Starting warmup iterations"
  # Warmup iterations first
  csystem("#{OPTS[:wrk_binary]} -t#{OPTS[:concurrency]} -c#{OPTS[:wrk_connections]} -d#{OPTS[:warmup_seconds]}s -s#{OPTS[:script_location]} --latency #{OPTS[:url]} > warmup_output_#{OPTS[:timestamp]}.txt", "Couldn't run warmup iterations!")

  verbose "Starting real benchmark iterations"
  csystem("#{OPTS[:wrk_binary]} -t#{OPTS[:concurrency]} -c#{OPTS[:wrk_connections]} -d#{OPTS[:benchmark_seconds]}s -s#{OPTS[:script_location]} --latency #{OPTS[:url]} > benchmark_output_#{OPTS[:timestamp]}.txt", "Couldn't run warmup iterations!")
end

raise "URL #{OPTS[:url].inspect} should not be available after the kill command (#{OPTS[:server_kill_matcher].inspect})!" if server_env.url_available?

# Read wrk's output, parse into our own output array

File.unlink "warmup_output_#{OPTS[:timestamp]}.txt"
File.unlink "benchmark_output_#{OPTS[:timestamp]}.txt"

json_text = JSON.pretty_generate(output)
File.open(OPTS[:out_file], "w") do |f|
  f.write json_text
end
