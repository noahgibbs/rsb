require_relative "bench_lib"
include BenchLib

require "optparse"
require "json"

# Functionality:
#
# * Multiple RVM rubies - use "rvm do", name Gemfiles for RVM name and/or set BUNDLE_GEMFILE; run this script w/ Ruby version configured
# * Server - allow passing in server string, use begin/ensure/end to run server and kill before exiting
# * Client - require ApacheBench - configuring concurrency is easy, but writing out correct data format is hard.

OPTS = {
  warmup_iters: 100,
  benchmark_iters: 100_000,
  port: 4323,
  concurrency: 1,
  url: "http://127.0.0.1:PORT/simple_bench/static",
  server_pre_cmd: "bundle exec rake db:migrate"
  server_cmd: "rackup -p PORT",
  out_file: "rsb_output.json",
  verbose: true,
}

OptionParser.new do |opts|
  opts.banner = <<BANNER
Usage: ruby rails_bench.rb [options]

URL format: the first instance of the following strings will be replaced automatically if present:

  PORT: the port number for the benchmark server

Defaults:

  port: #{port}
  url: #{url}
  warmup iterations: #{warmup_iters}
  benchmark iterations: #{benchmark_iters}
  concurrency: #{concurrency}
  out_file: #{out_file.inspect}
BANNER
  opts.on("-w", "--warmup-iterations NUMBER", "number of warmup iterations") do |n|
    OPTS[:warmup_iters] = n.to_i
  end
  opts.on("-n", "--num-iterations", "number of benchmarked iterations") do |n|
    OPTS[:benchmark_iters] = n.to_i
  end
  opts.on("-c", "--ab-concurrency", "number of concurrent ApacheBench (ab) requests") do |n|
    OPTS[:concurrency] = n.to_i
  end
  opts.on("-u", "--url", "The URL to benchmark") do |u|
    OPTS[:url] = u
  end
  opts.on("-p", "--port", "port number for Rails server") do |p|
    OPTS[:port] = p.to_i
  end
  opts.on("--server-command", "Command to run server (and check process list for running server)") do |sc|
    OPTS[:server_cmd] = sc
  end
  opts.on("--server-pre-command", "Command to run before starting server") do |spc|
    OPTS[:server_pre_cmd] = spc
  end
  opts.on("-o", "--output STRING", "output filename") do |p|
    OPTS[:out_file] = p
  end
end

if ARGV != []
    raise "Illegal or unexpected extra arguments: #{ARGV.inspect}"
end

which_ab = `which ab`
unless which_ab && which_ab != ""
    raise "No ApacheBench binary in path! On Ubuntu, sudo apt-get install apache2-utils."
end

# In both url and the server command, the port number may be written as PORT
OPTS[:url] = OPTS[:url].sub("PORT", OPTS[:port].to_s)
OPTS[:server_cmd] = OPTS[:server_cmd].sub("PORT", OPTS[:port].to_s)

env_vars = ENV.keys
important_env_vars = ["LD_PRELOAD"] + env_vars.select { |name| name.downcase["ruby"] || name.downcase["gem"] }
env_hash = {}
important_env_vars.each { |var| env_hash["env-#{var}"] = ENV[var] }

# Information about the host we're running on
output = {
    "version" => 1, # version of output format
    "settings" => OPTS,  # command-line and environmental settings for this script
    "environment" => {
        "RUBY_VERSION" => RUBY_VERSION,
        "RUBY_DESCRIPTION" => RUBY_DESCRIPTION,
        "rvm current" => `rvm current 2>&1`.strip,
        "repo git sha" => `cd #{__dir__} && git rev-parse HEAD`.chomp,
        "repo status" => `cd #{__dir__} && git status`,
        "ec2 instance id" => `wget -q -O - http://169.254.169.254/latest/meta-data/instance-id`,
        "ec2 instance type" => `wget -q -O - http://169.254.169.254/latest/meta-data/instance-type`,
        "ab_path" => which_ab,
        "uname" => `uname -a`,
    }.merge(env_hash),
}

def running_server_pids
  procs = `ps x | grep "#{OPTS[:server_cmd]} | grep -v grep | cut -f1 -d"`
  return [] if procs.strip == ""
  procs.split("\n").map(&:to_i)
end

def server_cleanup
  pids = running_server_pids
  return if pids == []
  pids.each { |pid| Process.kill "HUP", pid }
  sleep 1
  pids = running_server_pids
  pids.each { |pid| Process.kill "KILL", pid }
end

def start_server
  csystem("#{OPTS[:server_cmd]} &", "Can't run server!")
end

def url_available?
  system("curl #{OPTS[:url]}")
end

def ensure_url_available
  100.times do
    return true if url_available?
    sleep 0.3
  end
end

gnuplot_file = "#{Time.now.to_i}_bench_rsb.gnuplot"

server_cleanup # make sure the server isn't running already
begin
  csystem("bundle install", "Couldn't install/verify gems for server process!")
  csystem("#{OPTS[:server_pre_cmd]}", "Couldn't run precommand(s) (#{OPTS[:server_pre_cmd].inspect}) for server process!")

  raise "URL should not be available before the server runs!" if url_available?

  start_server
  ensure_url_available  # This may take up to 30ish seconds

  # Warmup iterations first
  csystem("ab -c #{OPTS[:concurrency]} -n #{OPTS[:warmup_iters]} #{OPTS[:url]}")

  # Then final iterations, saved to a GNUPlot file - this may be quite large
  csystem("ab -c #{OPTS[:concurrency]} -n #{OPTS[:warmup_iters]} #{OPTS[:url]} -g #{gnuplot_file}")
ensure
  server_cleanup # before the benchmark finishes, make sure the server is dead
end

# Now we've collected the data from ApacheBench. Time to parse the GNUplot file and rewrite to JSON.
