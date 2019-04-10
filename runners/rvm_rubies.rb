#!/usr/bin/env ruby

# This is both an example of a Ruby-based runner, and a way to run the benchmark for all the
# current "blessed" test Rubies - one per minor version of Ruby starting with 2.0.0, plus 2.0.0p0 itself
# as the baseline.

# For this, I just provide a set of options in Ruby instead of trying to use the command line to set up the
# quite large configuration.

require_relative "../bench_lib"
include BenchLib
include BenchLib::OptionsBuilder

# This example runner is configured using environment variables.
# If this looks awkward for simple cases... Well, you can write
# a much simpler runner by doing all your config directly in Ruby.
# See current_ruby.rb in this directory for an example.

# RSB_RUBIES: if set, use this space-separated list of RVM rubies instead of the "canonical" CRubies
# RSB_NUM_RUNS: number of runs/Ruby (default 10)
# RSB_RANDOM_SEED: random seed for randomizing order of trials (optional)
# RSB_DURATION: number of seconds to load-test for (default: 120)
# RSB_WARMUP: number of seconds of warmup load-testing (default: 15)
# RSB_WRK_CONCURRENCY: number of concurrent load-test connections active (default: 1)
# RSB_WRK_CONNECTIONS: number of connections created by load-tester (default: 60)
# RSB_URL: URL to test (default: http://127.0.0.1:PORT/static)

# RSB_APP_SERVER: app server, currently 'webrick' or 'puma' (default: webrick)
# RSB_PUMA_PROCESSES: if using Puma, number of processes (default: 4)
# RSB_PUMA_THREADS: if using Puma, threads/process (default: 5)

# RSB_DEBUG_SERVER: if true, show server output instead of suppressing it. Some errors are fine, others not... :-/

OPTS = {}

OPTS[:ruby_versions] = ENV["RSB_RUBIES"] ? ENV["RSB_RUBIES"].split(" ").compact : %w(2.0.0-p0 2.0.0-p648 2.1.10 2.2.10 2.3.8 2.4.5 2.5.3 2.6.0)
OPTS[:url] = ENV["RSB_URL"] || "http://127.0.0.1:PORT/static"
OPTS[:app_server] = ENV["RSB_APP_SERVER"] ? ENV["RSB_APP_SERVER"].downcase : "webrick"
raise "Unknown app server: #{OPTS[:app_server].inspect}!" unless ["puma", "webrick"].include?(OPTS[:app_server])
OPTS[:suppress_server_output] = ENV["RSB_DEBUG_SERVER"] ? false : true

# Integer environment parameters
[
  ["RSB_NUM_RUNS", :num_runs, 10],  # How many runs for each Ruby version
  ["RSB_RANDOM_SEED", :random_seed, Time.now.to_i],
  ["RSB_WARMUP", :warmup_seconds, 15],
  ["RSB_DURATION", :benchmark_seconds, 120],
  ["RSB_WRK_CONCURRENCY", :wrk_concurrency, 1],
  ["RSB_WRK_CONNECTIONS", :wrk_connections, 60],
  ["RSB_PUMA_PROCESSES", :puma_processes, 4],
  ["RSB_PUMA_THREADS", :puma_threads, 5],
].each do |env_name, opt_name, default_val|
  OPTS[opt_name] = ENV[env_name] ? ENV[env_name].to_i : default_val
end

puts "Current-run Options:\n#{JSON.pretty_generate OPTS}\n\n"

# Generate run arrays as the power set of (1..num_runs) x [:rails, :rack] x ruby_versions
runs = OPTS[:ruby_versions].flat_map do |rv|
  [:rails, :rack].flat_map { |rr| (1..(OPTS[:num_runs])).map { |run_idx| [ rv, rr, run_idx ] } }
end

# Randomize the order of the runs.
# A random seed can allow repeatability, which is normally only for debugging heisenbugs.
# But I'll print it out in case you get a weird bad run and need to make it happen again.
puts "Random seed: #{OPTS[:random_seed]}"
srand(OPTS[:random_seed])
runs = runs.sample(runs.size)

# Keep track of information as the runs complete
COUNTERS = {
  runs: 0,
  runs_success: 0,
  runs_failure: 0,
  runs_errors: 0,
}

def run_benchmark(rvm_ruby_version, rack_or_rails, run_index)
  # This logic clearly wants to live in BenchLib. It'll happen at some point.
  rr_opts = case [OPTS[:app_server].to_sym, rack_or_rails]
  when [:webrick, :rack]
    webrick_rack_options
  when [:webrick, :rails]
    webrick_rails_options
  when [:puma, :rack]
    puma_rack_options(processes: OPTS[:puma_processes], threads: OPTS[:puma_threads])
  when [:puma, :rails]
    puma_rails_options(processes: OPTS[:puma_processes], threads: OPTS[:puma_threads])
  else
    raise "Unknown app-server/app-type combination: #{[OPTS[:app_server], rack_or_rails].inspect}"
  end

  opts = rr_opts.merge({
    # Wrk settings
    wrk_binary: "wrk",
    wrk_concurrency: OPTS[:wrk_concurrency],  # This is wrk's own "concurrency" setting for number of requests in flight
    wrk_connections: OPTS[:wrk_connections],  # Number of connections for wrk to create and use
    warmup_seconds: OPTS[:warmup_seconds],
    benchmark_seconds: OPTS[:benchmark_seconds],
    url: OPTS[:url],

    # Bundler/Rack/Gem/Env config
    bundler_version: "1.17.3",
    #bundle_gemfile: nil,      # If explicitly nil, don't set. If omitted, set to Gemfile.$ruby_version

    :verbose => 1,

    before_worker_cmd: "rvm use #{rvm_ruby_version} && bundle",  # Run before each batch
    bundle_gemfile: "Gemfile.#{rvm_ruby_version}",

    # Useful for debugging, annoying for day-to-day use
    suppress_server_output: OPTS[:suppress_server_output],
  })
  # Can't include this in the merge above or it'll overwrite Puma's extra_env
  opts[:extra_env]["RSB_RUN_INDEX"] = run_index

  begin
    COUNTERS[:runs] += 1
    env = nil

    Dir.chdir("#{rack_or_rails}_test_app") do
      print "Benchmarking Options:\n#{JSON.pretty_generate(opts)}\n\n"
      env = BenchmarkEnvironment.new opts
      env.run_wrk
    end

    # Did the run generate data?
    unless File.exist?(env.out_file)
      raise "No data found, bail to rescue clause"
    end
    COUNTERS[:runs_success] += 1

    # Did the run have a significant error rate?
    run_data = JSON.parse(File.read(env.out_file))
    error_count = run_data["requests"]["benchmark"]["errors"].values.inject(0, &:+)
    latencies = run_data["requests"]["benchmark"]["latencies"]
    req_count = latencies.each_slice(2).map { |a, b| b }.inject(0, &:+) # Run-length encoded array
    error_rate = error_count.to_f / req_count
    puts "Error rate: #{error_rate.inspect}"
    if error_rate > 0.0001
      COUNTERS[:runs_errors] += 1
      print "************\n************\n\n HIGH ERROR RATE DETECTED: #{error_rate.inspect}\n\n************\n************\n"
    end
  rescue RuntimeError => exc
    COUNTERS[:runs_failure] += 1
    puts "Caught exception in #{rack_or_rails} app: #{exc.message.inspect}"
    puts "Backtrace:\n#{exc.backtrace.join("\n")}"
    puts "#{rack_or_rails.to_s.capitalize} app for Ruby #{rvm_ruby_version.inspect} failed, but we'll keep going..."
  end
end

# Now for every random-ordered run, make it happen.
runs.each do |ruby_version, rails_or_rack, run_idx|
  run_benchmark(ruby_version, rails_or_rack, run_idx)
end

print "\n\n===================\n"
puts "#{COUNTERS[:runs]} total runs"
puts "#{COUNTERS[:runs_failure]} generated exceptions and/or produced no data file, and so did not complete successfully"
puts "#{COUNTERS[:runs_errors]} completed with data but had high error rates"

puts "#{COUNTERS[:runs_success] - COUNTERS[:runs_errors]}/#{COUNTERS[:runs]} completed successfully w/o high error rate"
