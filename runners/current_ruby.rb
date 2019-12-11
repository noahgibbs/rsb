#!/usr/bin/env ruby

# This is both an example of a Ruby-based runner, and a way to run the benchmark for supported
# Rubies. You may need to create a Gemfile.lock if you want something specific for your
# chosen Ruby.

require_relative "../bench_lib"
include BenchLib
include BenchLib::OptionsBuilder
include BenchLib::GemfileGenerator

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
  bundle_gemfile: nil, # Or: "Gemfile.#{ruby_version}",
  verbose: 1,
  suppress_server_output: true,  # Set to false to show server output on console

  get_final_mem: true,
}

bench_dir = "#{which_app}_test_app"

# Default concurrency
rr_opts = options_by_framework_and_server(which_app, server).merge(opts)
setup_gemfile(ruby_version, which_app, rr_opts)

# Finally, run the benchmark
Dir.chdir(bench_dir) do
  BenchmarkEnvironment.new(rr_opts).run_wrk
end
