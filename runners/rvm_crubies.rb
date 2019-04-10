#!/usr/bin/env ruby

# This is both an example of a Ruby-based runner, and a way to run the benchmark for all the
# current "blessed" test Rubies - one per minor version of Ruby starting with 2.0.0, plus 2.0.0p0 itself
# as the baseline.

# For this, I just provide a set of options in Ruby instead of trying to use the command line to set up the
# quite large configuration.

require_relative "../bench_lib"
include BenchLib
include BenchLib::OptionsBuilder

ruby_versions = %w(2.0.0-p0 2.0.0-p648 2.1.10 2.2.10 2.3.8 2.4.5 2.5.3 2.6.0)
num_runs = ENV["NUM_RUNS"] ? ENV["NUM_RUNS"].to_i : 10  # How many runs for each Ruby version
random_seed = Time.now.to_i

# Generate run arrays as the power set of (1..num_runs) x [:rails, :rack] x ruby_versions
runs = ruby_versions.flat_map do |rv|
  [:rails, :rack].flat_map { |rr| (1..(num_runs)).map { |run_idx| [ rv, rr, run_idx ] } }
end

# Randomize the order of the runs.
# A random seed can allow repeatability, which is normally only for debugging heisenbugs.
# But I'll print it out in case you get a weird bad run and need to make it happen again.
puts "Random seed: #{random_seed}"
srand(random_seed)
runs = runs.sample(runs.size)

def run_benchmark(rvm_ruby_version, rack_or_rails, run_index)
  rr_opts = nil
  if rack_or_rails == :rack
    rr_opts = webrick_rack_options
  elsif rack_or_rails == :rails
    rr_opts = webrick_rails_options
  else
    raise "Rack_or_rails must be either :rack or :rails, not #{rack_or_rails.inspect}!"
  end

  opts = rr_opts.merge({
    # Wrk settings
    wrk_binary: "wrk",
    wrk_concurrency: 1,            # This is wrk's own "concurrency" setting for number of requests in flight
    wrk_connections: 60,           # Number of connections for wrk to create and use
    warmup_seconds: 5,
    benchmark_seconds: 120,
    url: "http://127.0.0.1:PORT/static",

    # Bundler/Rack/Gem/Env config
    bundler_version: "1.17.3",
    #bundle_gemfile: nil,      # If explicitly nil, don't set. If omitted, set to Gemfile.$ruby_version

    :verbose => 1,

    before_worker_cmd: "rvm use #{rvm_ruby_version} && bundle",  # Run before each batch
    bundle_gemfile: "Gemfile.#{rvm_ruby_version}",
    extra_env: {
      "RSB_RUN_INDEX" => run_index,
    },

    # Useful for debugging, annoying for day-to-day use
    #suppress_server_output: false,
  })

  begin
    Dir.chdir("#{rack_or_rails}_test_app") do
      e = BenchmarkEnvironment.new opts
      e.run_wrk
    end
  rescue RuntimeError => exc
    puts "Caught exception in #{rack_or_rails} app: #{exc.message.inspect}"
    puts "Backtrace:\n#{exc.backtrace.join("\n")}"
    puts "#{rack_or_rails.to_s.capitalize} app for Ruby #{rvm_ruby_version.inspect} failed, but we'll keep going..."
  end
end

# Now for every random-ordered run, make it happen.
runs.each do |ruby_version, rails_or_rack, run_idx|
  run_benchmark(ruby_version, rails_or_rack, run_idx)
end
