#!/usr/bin/env ruby

# This is both an example of a Ruby-based runner, and a way to run the benchmark for all the
# current "blessed" test Rubies - one per minor version of Ruby starting with 2.0.0, plus 2.0.0p0 itself
# as the baseline.

# For this, I just provide a set of options in Ruby instead of trying to use the command line to set up the
# quite large configuration.

require_relative "../bench_lib"
include BenchLib

ruby_versions = %w(2.0.0-p0 2.0.0-p648 2.1.10 2.2.10 2.3.8 2.4.5 2.5.3 2.6.0)
num_runs = 10  # How many runs for each Ruby version
random_seed = Time.now.to_i

# Generate run arrays as the power set of (1..num_runs) x [:rails, :rack] x ruby_versions
runs = ruby_versions.flat_map do |rv|
  [:rails, :rack].flat_map { |rr| (1..(num_runs)).map { |run_idx| [ rv, rr, run_idx ] } }
end

# Randomize the order of the runs
puts "Random seed: #{random_seed}"  # A random seed *can* allow repeatability, which you usually don't need or want
srand(random_seed)
runs = runs.sample(runs.size)

def run_benchmark(rvm_ruby_version, rack_or_rails, run_index)
  shared_opts = {
      # Wrk settings
      wrk_binary: "wrk",
      wrk_concurrency: 1,            # This is wrk's own "concurrency" setting for number of requests in flight
      wrk_connections: 60,           # Number of connections for wrk to create and use
      warmup_seconds: 5,
      benchmark_seconds: 180,

      # Bundler/Rack/Gem/Env config
      bundler_version: "1.17.3",
      #bundle_gemfile: nil,      # If explicitly nil, don't set. If omitted, set to Gemfile.$ruby_version

      :verbose => 1,
  }

  ruby_opts = {
    before_worker: "rvm use #{rvm_ruby_version} && bundle",  # Run before each batch
    bundle_gemfile: "Gemfile.#{rvm_ruby_version}",
  }

  if rack_or_rails == :rack
    rr_opts = shared_opts.merge(ruby_opts).merge({
      # Benchmarking options
      url: "http://127.0.0.1:PORT/static",
      out_file: File.expand_path(File.join(__dir__, "..", "data", "rsb_rack_TIMESTAMP.json")),

      # Server environment options
      server_cmd: "bundle && bundle exec rackup -p PORT",
      server_pre_cmd: "bundle",
      server_kill_matcher: "rackup",
    })
  elsif rack_or_rails == :rails
    rr_opts = shared_opts.merge(ruby_opts).merge({
      # Benchmarking options
      url: "http://127.0.0.1:PORT/static",
      out_file: File.expand_path(File.join(__dir__, "..", "data", "rsb_rails_TIMESTAMP.json")),

      # Server environment options
      server_cmd: "bundle exec rails server -p PORT",
      server_pre_cmd: "bundle && bundle exec rake db:migrate",
      server_kill_matcher: "rails server",
    })
  else
    raise "Rack_or_rails must be either :rack or :rails, not #{rack_or_rails.inspect}!"
  end

  begin
    Dir.chdir("#{rack_or_rails}_test_app") do
      ENV["RSB_RUN_INDEX"] = run_index.to_s
      e = BenchmarkEnvironment.new rr_opts
      e.run_wrk
    end
  rescue RuntimeError => exc
    puts "Caught exception in #{rack_or_rails} app: #{exc.message.inspect}"
    puts "Backtrace:\n#{exc.backtrace.join("\n")}"
    puts "#{rack_or_rails.to_s.capitalize} app for Ruby #{rvm_ruby_version.inspect} failed, but we'll keep going..."
  end
end

runs.each do |ruby_version, rails_or_rack, run_idx|
  run_benchmark(ruby_version, rails_or_rack, run_idx)
end
