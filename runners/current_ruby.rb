#!/usr/bin/env ruby

# This is both an example of a Ruby-based runner, and a way to run the benchmark for all the
# current "blessed" test Rubies - one per minor version of Ruby starting with 2.0.0, plus 2.0.0p0 itself
# as the baseline.

# For this, I just provide a set of options in Ruby instead of trying to use the command line to set up the
# quite large configuration.

require_relative "../bench_lib"
include BenchLib

which_app = :rails  # Can also be :rack

ruby_version = `ruby -e "puts RUBY_VERSION"`.chomp

opts = {
  wrk_concurrency: 1,
  wrk_connections: 10,
  warmup_seconds: 5,
  benchmark_seconds: 20,
  url: "http://127.0.0.1:PORT/static",

  bundler_version: "1.17.3",
  bundle_gemfile: "Gemfile.#{ruby_version}",
  verbose: 1,

  # This interface needs to change. This line shouldn't be needed, but currently is.
  ruby_change_cmd: "ruby RUNNER_SCRIPT JSON_FILENAME",
}

rack_options = {
  # Benchmarking options
  out_file: File.expand_path(File.join(__dir__, "..", "data", "rsb_rack_TIMESTAMP.json")),

  # Server environment options
  server_cmd: "bundle && bundle exec rackup -p PORT",
  server_pre_cmd: "bundle",
  server_kill_matcher: "rackup",
}

rails_options = {
  # Benchmarking options
  out_file: File.expand_path(File.join(__dir__, "..", "data", "rsb_rails_TIMESTAMP.json")),

  # Server environment options
  server_cmd: "bundle exec rails server -p PORT",
  server_pre_cmd: "bundle && bundle exec rake db:migrate",
  server_kill_matcher: "rails server",
}

if which_app == :rack
  opts.merge!(rack_options)
elsif which_app == :rails
  opts.merge!(rails_options)
else
  raise "Uh-oh! Which_app isn't :rack or :rails!"
end

Dir.chdir("#{which_app}_test_app") do
  e = BenchmarkEnvironment.new opts
  e.run_wrk
end
