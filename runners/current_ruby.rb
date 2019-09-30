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
}

bench_dir = "#{which_app}_test_app"

# Default concurrency
rr_opts = options_by_framework_and_server(which_app, server).merge(opts)
extra_gems = rr_opts.delete(:extra_gems) || []

# Dynamic gemfile generation
if opts[:bundle_gemfile].nil? || opts[:bundle_gemfile] == "Gemfile.dynamic"
  File.open("#{bench_dir}/Gemfile.dynamic", "w") do |f|
    f.write(gemfile_contents(ruby_version, :cruby, which_app, extra_gems))
  end
  File.open("#{bench_dir}/Gemfile.dynamic.lock", "w") do |f|
    f.write(gemfile_lock_contents(ruby_version, :cruby, which_app, extra_gems))
  end
  rr_opts[:bundle_gemfile] = "Gemfile.dynamic" # Have to be able to find Gemfile.dynamic.lock
else
  rr_opts[:bundle_gemfile] = "#{bench_dir}/#{opts[:bundle_gemfile]}"
end

# Finally, run the benchmark
Dir.chdir(bench_dir) do
  BenchmarkEnvironment.new(rr_opts).run_wrk
end
