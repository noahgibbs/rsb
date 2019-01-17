#!/usr/bin/env ruby

require_relative "bench_lib"
include BenchLib

require "optparse"
require "date"
require "json"

OPTS = {
  warmup_iters: 100,
  benchmark_iters: 100_000,
  port: 4323,
  concurrency: 1,
  url: "http://127.0.0.1:PORT/simple_bench/static",
  server_pre_cmd: "bundle install && bundle exec rake db:migrate",
  server_cmd: "rackup -p PORT",
  server_kill_matcher: "rackup",
  out_file: "rsb_output_TIME.json",
  timestamp: Time.now.to_i,
  verbose: 1,
}

leftover_args = OptionParser.new do |opts|
  opts.banner = <<BANNER
Usage: ruby rails_bench.rb [options]

The first instance of the following strings will be replaced automatically if present
in URLs, output files or commands:

  PORT: the port number for the benchmark server
  TIMESTAMP: the number of integer seconds since Jan 1st, 1970 GMT that the benchmark runs

Defaults:

#{OPTS.map { |key, val| "#{key}: #{val}" }.join("\n")}

Specific options:
BANNER
  opts.on("-w NUMBER", "--warmup-iterations NUMBER", Integer, "number of warmup iterations") do |n|
    OPTS[:warmup_iters] = n.to_i
  end
  opts.on("-n NUMBER", "--num-iterations NUMBER", Integer, "number of benchmarked iterations") do |n|
    OPTS[:benchmark_iters] = n
    unless n % 100 == 0
      puts "Warning: if the benchmark iterations aren't a multiple of 100, you may get unexpected percentile behavior when data processing..."
    end
  end
  opts.on("-c NUMBER", "--ab-concurrency NUMBER", Integer, "number of concurrent ApacheBench (ab) requests") do |n|
    OPTS[:concurrency] = n
  end
  opts.on("-u URL", "--url URL", "The URL to benchmark") do |u|
    OPTS[:url] = u
  end
  opts.on("-p NUMBER", "--port NUMBER", Integer, "port number for Rails server") do |p|
    OPTS[:port] = p
  end
  opts.on("--server-command CMD", "Command to run server (and check process list for running server)") do |sc|
    OPTS[:server_cmd] = sc
  end
  opts.on("--server-pre-command CMD", "Command to run before starting server") do |spc|
    OPTS[:server_pre_cmd] = spc
  end
  opts.on("--server-kill-match CMD", "String to match when killing processes") do |skm|
    OPTS[:server_kill_matcher] = skm
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

which_ab = `which ab`
unless ApacheBenchClient.installed?
    raise "No ApacheBench binary in path! On Ubuntu, sudo apt-get install apache2-utils."
end

# In some options, there's a text substitution for variables like PORT and TIMESTAMP
[:url, :server_cmd, :server_pre_cmd, :server_kill_matcher, :out_file].each do |opt|
  OPTS[opt].gsub! "PORT", OPTS[:port].to_s
  OPTS[opt].gsub! "TIMESTAMP", OPTS[:timestamp].to_s
end

env_vars = ENV.keys
important_env_vars = ["LD_PRELOAD"] + env_vars.select { |name| name.downcase["ruby"] || name.downcase["gem"] || name.downcase["rsb"] }
env_hash = {}
important_env_vars.each { |var| env_hash["env-#{var}"] = ENV[var] }

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
                                   url: OPTS[:url]

def verbose(str)
  puts str if OPTS[:verbose] > 0
end

gnuplot_file = "#{OPTS[:timestamp]}_bench_rsb.gnuplot"
csv_file = "#{OPTS[:timestamp]}_bench_rsb.csv"

server_env.server_cleanup # make sure the server isn't running already

#csystem("bundle install", "Couldn't install/verify gems for server process!")

raise "URL #{OPTS[:url].inspect} should not be available before the server runs!" if server_env.url_available?

server_env.with_url_available do
  puts "Starting warmup iterations"
  # Warmup iterations first
  csystem("ab -c #{OPTS[:concurrency]} -n #{OPTS[:warmup_iters]} #{OPTS[:url]}", "Couldn't run warmup iterations!")

  puts "Starting real benchmark iterations"
  # Then final iterations, saved to a GNUPlot file - this may be quite large
  csystem("ab -c #{OPTS[:concurrency]} -n #{OPTS[:benchmark_iters]} -g #{gnuplot_file} #{OPTS[:url]}", "Couldn't run benchmark iterations!")
end

raise "URL #{OPTS[:url].inspect} should not be available after the kill command (OPTS[:server_kill_substring])!" if server_env.url_available?

# Now we've collected the data from ApacheBench. Time to parse the GNUplot file and rewrite to JSON.
starttimes = Hash.new(0)
File.open(gnuplot_file, "r") do |f|
  headers = nil
  f.each_line do |line|
    if headers
      starttime, seconds, ctime, dtime, ttime, wait = line.split("\t")
      starttime = DateTime.parse(starttime).to_time.to_i
      output["requests"]["benchmark"] << dtime.to_i
      starttimes[starttime] += 1
    else
      headers = line.split("\t")
    end
  end
end

output["requests"]["max_starttime"] = starttimes.keys.max
output["requests"]["min_starttime"] = starttimes.keys.min
output["requests"]["starttime_hist"] = starttimes

json_text = JSON.pretty_generate(output)
File.open(OPTS[:out_file], "w") do |f|
  f.write json_text
end
File.unlink gnuplot_file
