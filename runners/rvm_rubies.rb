#!/usr/bin/env ruby

# This is both an example of a Ruby-based runner, and a way to run the
# benchmark for all the current "blessed" test Rubies - one per minor
# version of Ruby starting with 2.0.0, plus 2.0.0p0 itself as the
# baseline.

# This runner is configured using environment variables. If this looks
# awkward for simple cases, keep in mind that you can write a much
# simpler runner by doing all your config directly in Ruby. See
# current_ruby.rb in this directory for an example.

# This is also an example of a runner that is error-tolerant but
# error-aware. That's not a good default for every case, but it can be
# very useful for large batches and long runs.

# Configuration Environment Variables:

# RSB_RUBIES: if set, use this space-separated list of RVM rubies instead of the "canonical" CRubies
# RSB_FRAMEWORKS: if set to "rails" or "rack", only use that one instead of both. Can also be set to "rails rack" or "rack rails" for default behavior.
# RSB_GEMFILE: if set to Dynamic or unset, use Dynamic; if set to a different value, use as the Gemfile
# RSB_NUM_RUNS: number of runs/Ruby (default 10)
# RSB_RANDOM_SEED: random seed for randomizing order of trials (optional)
# RSB_DURATION: number of seconds to load-test for (default: 120)
# RSB_WARMUP: number of seconds of warmup load-testing (default: 15)
# RSB_WRK_CONCURRENCY: number of concurrent load-test connections active (default: 1)
# RSB_WRK_CONNECTIONS: number of connections created by load-tester (default: 60)
# RSB_URL: URL to test (default: http://127.0.0.1:PORT/static)

# RSB_APP_SERVER: app server, currently 'webrick' or 'puma' (default: puma)
# RSB_PROCESSES: number of processes (default: 1)
# RSB_THREADS: number of threads per process (default: 1)

# RSB_CLOSE_CONNECTION: if true, specify the connection-close header when using wrk; needed for good JRuby performance on Puma
# RSB_DEBUG_SERVER: if true, show server output instead of suppressing it. Some errors are fine, others not... :-/

# RSB_COMPACT: turn on manual memory compaction via GC.compact (note: should only be allowed for Ruby 2.7+ and only useful for 2.7-series Rubies)
# RSB_GET_FINAL_MEM: query the Ruby process's memory usage after all requests have finished

KNOWN_ENV_VARS = [
  "RSB_RUBIES", "RSB_FRAMEWORKS", "RSB_NUM_RUNS", "RSB_RANDOM_SEED", "RSB_DURATION", "RSB_WARMUP",
  "RSB_WRK_CONCURRENCY", "RSB_WRK_CONNECTIONS", "RSB_URL", "RSB_APP_SERVER", "RSB_PROCESSES",
  "RSB_THREADS", "RSB_DEBUG_SERVER", "RSB_CLOSE_CONNECTION", "RSB_COMPACT", "RSB_GET_FINAL_MEM",
  "RSB_GEMFILE",
]

require_relative "../bench_lib"
include BenchLib
include BenchLib::OptionsBuilder

OPTS = {}

OPTS[:frameworks] = ENV["RSB_FRAMEWORKS"] ? ENV["RSB_FRAMEWORKS"].split(" ").compact : %w(rails rack)
OPTS[:frameworks] = OPTS[:frameworks].map(&:to_sym)

OPTS[:ruby_versions] = ENV["RSB_RUBIES"] ? ENV["RSB_RUBIES"].split(" ").compact : %w(2.0.0-p0 2.0.0-p648 2.1.10 2.2.10 2.3.8 2.4.5 2.5.3 2.6.0)
OPTS[:url] = ENV["RSB_URL"] || "http://127.0.0.1:PORT/static"
OPTS[:app_server] = (ENV["RSB_APP_SERVER"] ? ENV["RSB_APP_SERVER"].downcase : "puma").to_sym
raise "Unknown app server: #{OPTS[:app_server].inspect}, must be one of #{BenchLib::OptionsBuilder::APP_SERVERS.map(&:to_s).inspect}!" unless BenchLib::OptionsBuilder::APP_SERVERS.include?(OPTS[:app_server])
OPTS[:suppress_server_output] = ENV["RSB_DEBUG_SERVER"] ? false : true
OPTS[:wrk_close_connection] = ENV["RSB_CLOSE_CONNECTION"] ? true : false
OPTS[:rack_env] = ENV["RACK_ENV"] || ENV["RAILS_ENV"] || "production"
OPTS[:compact] = ENV["RSB_COMPACT"] ? true : false
OPTS[:get_final_mem] = ENV["RSB_GET_FINAL_MEM"] ? true : false
OPTS[:rsb_gemfile] = ENV["RSB_GEMFILE"] || "dynamic"

# Integer environment parameters
[
  ["RSB_NUM_RUNS", :num_runs, 10],  # How many runs for each Ruby version
  ["RSB_RANDOM_SEED", :random_seed, Time.now.to_i],
  ["RSB_WARMUP", :warmup_seconds, 15],
  ["RSB_DURATION", :benchmark_seconds, 120],
  ["RSB_WRK_CONCURRENCY", :wrk_concurrency, 1],
  ["RSB_WRK_CONNECTIONS", :wrk_connections, 60],
  ["RSB_PROCESSES", :processes, 1],
  ["RSB_THREADS", :threads, 1],
].each do |env_name, opt_name, default_val|
  OPTS[opt_name] = ENV[env_name] ? ENV[env_name].to_i : default_val
end

rsb_env_keys = ENV.keys.grep(/^RSB_/)
unknown_keys = rsb_env_keys - KNOWN_ENV_VARS
unless unknown_keys.empty?
  puts "WARNING: Unknown environment variables starting with RSB_: #{unknown_keys.inspect}..."
  puts "WARNING: Settings in these variables WILL NOT have any effect on RSB's behavior."
end

puts "Current-run Options:\n#{JSON.pretty_generate OPTS}\n\n"

# Generate run arrays as the power set of (1..num_runs) x frameworks x ruby_versions
runs = OPTS[:ruby_versions].flat_map do |rv|
  OPTS[:frameworks].flat_map { |rr| (1..(OPTS[:num_runs])).map { |run_idx| [ rv, rr, run_idx ] } }
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
  rr_opts = options_by_framework_and_server(rack_or_rails, OPTS[:app_server], processes: OPTS[:processes], threads: OPTS[:threads])
  extra_gems = rr_opts.delete(:extra_gems) || [] # Can be used for dynamic Gemfile generation

  opts = rr_opts.merge({
    # Wrk settings
    wrk_binary: "wrk",
    wrk_concurrency: OPTS[:wrk_concurrency],  # This is wrk's own "concurrency" setting for number of requests in flight
    wrk_connections: OPTS[:wrk_connections],  # Number of connections for wrk to create and use
    wrk_close_connection: OPTS[:wrk_close_connection],
    warmup_seconds: OPTS[:warmup_seconds],
    benchmark_seconds: OPTS[:benchmark_seconds],
    url: OPTS[:url],

    # Bundler/Rack/Gem/Env config
    bundler_version: "1.17.3",
    #bundle_gemfile: nil,      # If explicitly nil, don't set. If omitted, set to Gemfile.$ruby_version

    :verbose => 1,

    wrap_subprocess_cmd: "bash -l -c \"rvm use #{rvm_ruby_version} && COMMAND\"",
    bundle_gemfile: "Gemfile.#{rvm_ruby_version}",

    # Useful for debugging, annoying for day-to-day use
    suppress_server_output: OPTS[:suppress_server_output],
  })
  if OPTS[:rsb_gemfile].downcase == "dynamic"
    # Dynamic Gemfile generation
    opts[:bundle_gemfile] = "dynamic"
  else
    # Set to something, but not Dynamic - use what was requested.
    # This changes the default to using dynamic Gemfile generation!
    # For most people, this is clearly an improvement.
    # I'd worry more if this runner were frequently used.
    opts[:bundle_gemfile] = OPTS[:rsb_gemfile]
  end
  opts[:extra_env] ||= {}
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
