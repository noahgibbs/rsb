require_relative "../bench_lib"

require "minitest"
require "minitest/autorun"

class TestSubprocess < Minitest::Test
  include BenchLib
  include BenchLib::OptionsBuilder

  def setup
  end

  def teardown
  end

  def test_basic_runner
    opts = {
      # Test-specific settings to stub out the real benchmark functionality
      wrk_binary: File.expand_path(File.join __dir__, "cat_args.sh"),
      ruby_subprocess_cmd: "ruby SUBPROCESS_SCRIPT JSON_FILENAME",
      server_cmd: "echo server",
      server_pre_cmd: "echo pre-server",
      server_kill_command: "echo killing server",
      no_check_url: true,

      wrk_concurrency: 3,
      wrk_connections: 4,
      wrk_close_connection: false,
      warmup_seconds: 7,
      benchmark_seconds: 9,
      url: "http://127.0.0.1:PORT/someurl",

      bundle_gemfile: "Gemfile.test_subprocess",
      verbose: 1,
    }

    begin
      # Remove if present
      File.unlink '/tmp/rsb_subprocess_args.txt'
    rescue Errno::ENOENT
      # No problem
    end
    Dir.chdir(File.expand_path(File.join __dir__, "..", "rails_test_app")) do
      begin
        BenchmarkEnvironment.new(opts).run_wrk
      rescue err
        # This is expected to fail. Let's make sure it fails because the fake
        # wrk binary didn't return error but also didn't create a file.
        assert err.message["Could not locate latency data"], "Error had unexpected message: #{err.message.inspect}"
      end
    end

    wrk_args = File.read('/tmp/rsb_subprocess_args.txt')
    STDERR.puts "WRK ARGS: #{wrk_args.inspect}"
    assert_equal <<EXPECTED, wrk_args
-t3 -c4 -d7s -s/Users/noah.gibbs/src/ruby/rsb/./final_report.lua --latency http://127.0.0.1:4321/someurl
-t3 -c4 -d9s -s/Users/noah.gibbs/src/ruby/rsb/./final_report.lua --latency http://127.0.0.1:4321/someurl
EXPECTED
    File.unlink '/tmp/rsb_subprocess_args.txt'
  end
end
