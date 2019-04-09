#!/usr/bin/env ruby

# This is both an example of a Ruby-based runner, and a way to run the benchmark for all the
# current "blessed" test Rubies - one per minor version of Ruby starting with 2.0.0, plus 2.0.0p0 itself
# as the baseline.

# For this, I just provide a set of options in Ruby instead of trying to use the command line to set up the
# quite large configuration.

require_relative "../bench_lib"
include BenchLib

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

%w(2.0.0-p0 2.0.0-p648 2.1.10 2.2.10 2.3.8 2.4.5 2.5.3 2.6.0).each do |rvm_ruby_version|
  ruby_opts = {
    rvm_ruby_version: rvm_ruby_version,
    bundle_gemfile: "Gemfile.#{rvm_ruby_version}",
  }

  begin
    rails_opts = shared_opts.merge(ruby_opts).merge({
      # Benchmarking options
      url: "http://127.0.0.1:PORT/simple_bench/static",
      out_file: File.expand_path(File.join(__dir__, "..", "data", "rsb_rails_TIMESTAMP.json")),

      # Server environment options
      server_cmd: "bundle exec rails server -p PORT",
      server_pre_cmd: "bundle && bundle exec rake db:migrate",
      server_kill_matcher: "rails server",
    })
    Dir.chdir("rails_test_app") do
      e = BenchmarkEnvironment.new rails_opts
      e.run_wrk
    end
  rescue RuntimeError => exc
    puts "Caught exception in Rails app: #{exc.message.inspect}"
    puts "Backtrace:\n#{exc.backtrace.join("\n")}"
    puts "Rails app for Ruby #{rvm_ruby_version.inspect} failed, but we'll keep going..."
  end

  begin
    rack_opts = shared_opts.merge(ruby_opts).merge({
      # Benchmarking options
      url: "http://127.0.0.1:PORT/simple_bench/static",
      out_file: File.expand_path(File.join(__dir__, "..", "data", "rsb_rack_TIMESTAMP.json")),

      # Server environment options
      server_cmd: "bundle && bundle exec rackup -p PORT",
      server_pre_cmd: "bundle",
      server_kill_matcher: "rackup",
    })
    Dir.chdir("rack_test_app") do
      e = BenchmarkEnvironment.new rack_opts
      e.run_wrk
    end
  rescue RuntimeError => exc
    puts "Caught exception in Rack app: #{exc.message.inspect}"
    puts "Backtrace:\n#{exc.backtrace.join("\n")}"
    puts "Rack app for Ruby #{rvm_ruby_version.inspect} failed, but we'll keep going..."
  end
end