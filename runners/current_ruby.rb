#!/usr/bin/env ruby

# This is both an example of a Ruby-based runner, and a way to run the benchmark for all the
# current "blessed" test Rubies - one per minor version of Ruby starting with 2.0.0, plus 2.0.0p0 itself
# as the baseline.

# For this, I just provide a set of options in Ruby instead of trying to use the command line to set up the
# quite large configuration.

require_relative "../bench_lib"
include BenchLib
include BenchLib::OptionsBuilder

which_app = :rails  # Can also be :rack
server = :webrick   # Can also be :puma, :unicorn, :thin, :passenger

# This determines which Gemfile.lock is appropriate.
# There may not be a single most appropriate version, or you may
# need to create one.
ruby_version = `ruby -e "puts RUBY_VERSION"`.chomp

# See #BenchLib::SETTINGS_DEFAULTS for the various options
opts = {
  wrk_concurrency: 1,
  wrk_connections: 10,
  wrk_close_connection: true,
  warmup_seconds: 5,
  benchmark_seconds: 20,
  url: "http://127.0.0.1:PORT/static",

  bundler_version: nil, # "1.17.3",
  bundle_gemfile: "Gemfile.#{ruby_version}",
  verbose: 1,
}

# Default concurrency
opts = options_by_framework_and_server(which_app, server).merge(opts)
extra_gems = rr_opts.delete(:extra_gems) || [] # Can be used for dynamic Gemfile generation

# Here's the meat of how to turn those options into benchmark output
Dir.chdir("#{which_app}_test_app") do
  BenchmarkEnvironment.new(opts).run_wrk
end
