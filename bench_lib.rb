# This library is used by runners to set up benchmark runs.
# See the "runners" directory for the normal interface to
# this code.

# There are multiple interfaces here which could easily be
# separated:
#
# * the ServerEnvironment runs a server and shuts it down.
# * the BenchmarkEnvironment spawns a child process to perform a full benchmark.
# * the OptionsBuilder makes it easier to generate the options hash for BenchmarkEnvironment.

require "json"
require "bundler"
require "timeout"

module BenchLib

  SETTINGS_DEFAULTS = {
      # Wrk settings
      wrk_binary: "wrk",
      wrk_concurrency: 1,            # This is wrk's own "concurrency" setting for number of requests in flight
      wrk_connections: 100,          # Number of connections for wrk to create and use
      wrk_script_location: "./final_report.lua",  # This is the lua script for generating the final report, relative to this source file
      wrk_close_connection: false,

      warmup_seconds: 5,
      benchmark_seconds: 180,

      # Runner Config
      before_worker_cmd: "bundle install",
      ruby_subprocess_cmd: "bash -l -c \"BEFORE_WORKER && ruby SUBPROCESS_SCRIPT JSON_FILENAME\"",
      json_filename: "/tmp/benchlib_#{Process.pid}.json",
      wrk_subprocess: File.expand_path(File.join(__dir__, "wrk_subprocess.rb")),

      # Bundler/Rack/Gem/Env config
      rack_env: "production", # Sets both $RACK_ENV and $RAILS_ENV
      bundle_gemfile: nil,    # If supplied, set BUNDLE_GEMFILE to value.
      bundler_version: nil,   # If supplied, set BUNDLER_VERSION to value.
      extra_env: {},          # Additional environment variables to set.

      # Benchmarking options
      port: 4321,
      timestamp: nil,
      url: "http://127.0.0.1:PORT/simple_bench/static",
      out_file: "data/rsb_output_TIME.json",
      verbose: 1,

      # Server environment options
      server_cmd: nil,      # This command should start the server
      server_ruby_opts: nil, # Additional ruby options passed to the server process
      server_pre_cmd: nil,  # This command is run at least once before starting the server
      server_kill_command: nil,  # This is a command which, if run, should kill the server - only use *one* of kill command or kill matcher
      server_kill_matcher: nil,  # This is a string which, if matched, means "kill this process when killing server" - only use *one* of kill command or kill matcher
      suppress_server_output: true,
      no_check_url: false,  # Don't check that the server actually opens/closes the appropriate PORT number
  }

  # Checked system - error if the command fails
  def csystem(cmd, err, debug: true, fail_ok: false, console: true)
    puts "Running command: #{cmd}" if debug
    if console
      if RUBY_PLATFORM == "java"
        system(cmd)
      else
        system(cmd, out: $stdout, err: $stderr)
      end
    else
      out = `#{cmd}`
    end
    unless $?.success? || fail_ok
      puts "Error running command:\n#{cmd.inspect}"
      puts "Output:\n#{out}\n=====" unless console
      raise err
    end
  end

  # system_environment returns the unlikely-to-change portions of the process's environment
  # in order to tag the data file.
  def system_environment
    {
        "RUBY_VERSION" => RUBY_VERSION,
        "RUBY_DESCRIPTION" => RUBY_DESCRIPTION,
        "rvm current" => `rvm current 2>&1`.strip,
        "repo git sha" => `cd #{__dir__} && git rev-parse HEAD`.chomp,
        "repo status" => `cd #{__dir__} && git status`,
        #"ec2 instance id" => `wget -q -O - http://169.254.169.254/latest/meta-data/instance-id`,
        #"ec2 instance type" => `wget -q -O - http://169.254.169.254/latest/meta-data/instance-type`,
        "uname" => `uname -a`,
        "dir" => Dir.pwd,
        "worker pid" => Process.pid,
    }
  end

  # ServerEnvironment starts and manages a Rails server to benchmark against.
  class ServerEnvironment
    def initialize(server_start_cmd = "rackup", server_ruby_opts: nil, server_pre_cmd: "echo Skipping", server_kill_substring: "rackup",
          server_kill_command: nil, self_name: "ab_bench", url: "http://localhost:3000", suppress_server_output: true,
          no_check_url: false)
      @server_start_cmd = server_start_cmd
      @server_ruby_opts = server_ruby_opts
      @server_pre_cmd = server_pre_cmd
      @server_kill_substring = server_kill_substring
      @server_kill_command = server_kill_command
      @self_name = self_name
      if @server_kill_substring && @server_kill_command
        raise "Can't supply both server kill command and server kill substring!"
      end
      @url = url
      @suppress_server_output = suppress_server_output
      @no_check_url = no_check_url
    end

    # Note: this only makes sense if we received @server_kill_substring, not @server_kill_command
    def running_server_pids
      ps_out = `ps x`
      proc_lines = ps_out.split("\n").select { |line| line[@server_kill_substring] && !line["grep"] && !line[@self_name] }
      proc_lines.map { |line| line.split(" ", 2)[0].to_i }
    end

    def server_cleanup
      if @server_kill_command
        return csystem(@server_kill_command, "Failure when running server kill command!", fail_ok: true)
      end
      pids = running_server_pids
      return if pids.empty?

      kill = -> signal do
        pids.each do |pid|
          begin
            Process.kill signal, pid
          rescue Errno::ESRCH
            # Already terminated
          end
        end
      end

      wait = -> do
        pids.each do |pid|
          begin
            Process.wait(pid)
          rescue Errno::ECHILD
            # Already waited on or server process of a previous run
          end
        end
      end

      kill.call(:SIGINT)
      begin
        Timeout.timeout(3) { wait.call }
      rescue Timeout::Error
        puts "Sending SIGKILL to #{pids} as they did not terminate in 3s after SIGINT"
        kill.call(:SIGKILL)
        wait.call
      end
    end

    def server_pre_cmd
      if @server_pid
        csystem("#{@server_pre_cmd}", "Couldn't run precommand(s) (#{@server_pre_cmd.inspect}) for server process!")
      end
    end

    def start_server
      redirects = {}
      redirects = { out: File::NULL, err: File::NULL } if @suppress_server_output
      server_command = "ruby #{@server_ruby_opts} -S #{@server_start_cmd}"
      puts "Running server: #{server_command} #{redirects}"
      @server_pid = spawn(server_command, redirects)
    end

    def url_available?
      system("curl #{@url} 1>/dev/null 2>&1")
      $?.success?  # Think I can just return the system line above - was having trouble because I was
      # using bash-specific syntax, which doesn't work on Linux /bin/sh...
    end

    def ensure_url_available
      return true if @no_check_url
      400.times do |i|
        return true if url_available?
        sleep 0.3
        if i % 30 == 2
          # How to output this most appropriately?
          puts "Still trying to connect..."
        end
      end
      abort "Could not connect to the server!"
    end

    def with_url_available
      server_pre_cmd
      start_server
      begin
        ensure_url_available
        yield
      ensure
        server_cleanup
      end
    end
  end

  # A BenchmarkEnvironment sets up the environment variables
  # and other system-level configuration for a ServerEnvironment to happen inside.
  #
  # WrkBenchRunner assumes that it will need to fork a separate subprocess to make all of this
  # happen - you can't easily set up a new Ruby/Bundler environment inside your same process
  # without serious side effects.
  #
  # Since a ServerEnvironment requires setting up a lot of configuration, a BenchEnvironment
  # subsumes it - it takes the configuration variables and runs the ServerEnvironment for you rather than having you juggle
  # it manually in between.
  #
  # The blessed method for running the benchmark is #run_wrk. See a runner script ending in the runners
  # directory for examples of how to use it.
  class BenchmarkEnvironment

    def initialize(settings = {})
      settings = BenchLib::SETTINGS_DEFAULTS.merge(settings) # Don't modify passed-in original

      illegal_keys = settings.keys - BenchLib::SETTINGS_DEFAULTS.keys
      raise "Illegal keys in settings: #{illegal_keys.inspect}!" unless illegal_keys.empty?
      @settings = settings

      settings[:timestamp] = Time.now.to_i unless settings[:timestamp]

      # Verify that wrk is installed and available
      if @settings[:wrk_binary] == "wrk"
        which_wrk = `which wrk`
        unless which_wrk && which_wrk.strip != ""
          raise "No wrk binary in path! Build or install the binary and/or specify a path!"
        end
      end

      # Perform text substitution on options
      # In some options, there's a text substitution for variables like PORT and TIMESTAMP
      [:url, :server_cmd, :server_pre_cmd, :server_kill_matcher, :server_kill_command,
        :out_file, :before_worker_cmd, :ruby_subprocess_cmd].each do |opt|
        next if @settings[opt].nil?
        @settings[opt] = @settings[opt].gsub "PORT", @settings[:port].to_s # Dup string on first gsub
        @settings[opt].gsub! "TIMESTAMP", @settings[:timestamp].to_s
        @settings[opt].gsub! "BEFORE_WORKER", @settings[:before_worker_cmd]
        @settings[opt].gsub! "JSON_FILENAME", @settings[:json_filename]
        @settings[opt].gsub! "SUBPROCESS_SCRIPT", @settings[:wrk_subprocess]
      end
    end

    # Output files are particularly liable to have TIMESTAMP substituted in
    # their name. This is a way to retrieve that without bending over *too*
    # far backward.
    def out_file
      @settings[:out_file]
    end

    # This starts a run of wrk by packaging up settings, setting up configuration,
    # forking a wrk_subprocess child process and passing everything through.
    #
    # Results will be in @settings[:out_file] once the child process has completed
    # successfully (if it does.)
    def run_wrk
      filename = @settings[:json_filename]
      File.open(filename, "w") { |f| f.write JSON.dump(@settings) }
      begin
        exec_with_config @settings[:ruby_subprocess_cmd]
      ensure
        File.unlink(filename)
      end
    end

    def exec_with_config(cmd_line)
      Bundler.with_clean_env do
        env = {}
        env["RACK_ENV"] = @settings[:rack_env]
        env["RAILS_ENV"] = @settings[:rack_env]
        if @settings[:bundle_gemfile]
          env["BUNDLE_GEMFILE"] = @settings[:bundle_gemfile]
        end
        if @settings[:bundler_version]
          env["BUNDLER_VERSION"] = @settings[:bundler_version]
        end
        if @settings[:extra_env]
          @settings[:extra_env].each { |k, v| env[k.to_s] = v.to_s }
        end
        verbose "exec: #{env.map { |k,v| "#{k}=#{v}" }.join(' ')} #{cmd_line}"
        system env, cmd_line
      end
    end

    def verbose(s)
      if @settings[:verbose]
        puts s
      end
    end

    def capture_environment
      env_vars = ENV.keys
      important_env_vars = ["LD_PRELOAD"] + env_vars.select { |name| name.downcase["ruby"] || name.downcase["gem"] || name.downcase["rsb"] }
      env_hash = {}
      important_env_vars.each { |var| env_hash["env-#{var}"] = ENV[var] }
      env_hash["wrk_path"] = `which wrk`

      # Information about the host we're running on
      {
          "version" => "wrk:2", # version of output format
          "settings" => @settings,  # command-line and environmental settings for this script
          "environment" => BenchLib.system_environment.merge(env_hash),
          "requests" => {
            "warmup" => {},
            "benchmark" => {},
            #"benchmark_min_starttime"
            #"benchmark_max_starttime"
          }
      }
    end

    def parse_wrk_into_stats(str)
      out = {}

      # The output is human-readable text, followed by the output of final_report.lua
      first, second = str.split("-- Final Report")

      if second =~ /^Latencies: \[(.*)\]$/
        out[:latencies] = $1.split(",")[0..-2].map(&:to_i) # There's a final comma that shows up as a blank
      else
        raise "Could not locate latency data!"
      end
      out[:latencies].pop if out[:latencies][-1] == 0

      if second =~ /^Per-Thread ReqsPerSec: \[(.*)\]$/
        out[:req_per_sec] = $1.split(",")[0..-2].map(&:to_i)# There's a final comma that shows up as a blank
      else
        raise "Could not locate requests/sec data!"
      end

      if second =~ /^Summary Errors: connect:([0-9]+),read:([0-9]+),write:([0-9]+),status:([0-9]+),timeout:([0-9]+)$/
        out[:errors] = {
          connect: $1.to_i,
          read: $2.to_i,
          write: $3.to_i,
          status: $4.to_i,
          timeout: $5.to_i,
        }
      else
        raise "Could not locate error data!"
      end
      out
    end

    # This is run by the child process's wrk_subprocess.rb as a top-level method
    def subprocess_main
      output = capture_environment

      server_env = ServerEnvironment.new @settings[:server_cmd],
                                         server_ruby_opts: @settings[:server_ruby_opts],
                                         server_pre_cmd: @settings[:server_pre_cmd],
                                         server_kill_substring: @settings[:server_kill_matcher],
                                         server_kill_command: @settings[:server_kill_command],
                                         self_name: "wrk_bench",
                                         url: @settings[:url],
                                         suppress_server_output: @settings[:suppress_server_output],
                                         no_check_url: @settings[:no_check_url]

      # If we know how to make sure the server isn't running, do that.
      if @settings[:server_kill_matcher]
        server_env.server_cleanup
      end

      if !@settings[:no_check_url] && server_env.url_available?
        raise "URL #{@settings[:url].inspect} should not be available before the server runs!"
      end

      server_env.with_url_available do
        wrk_script_location = File.join(__dir__, @settings[:wrk_script_location])
        wrk_close_header_opts = @settings[:wrk_close_connection] ? '--header "Connection: Close"' : ""
        wrk_command = -> mode do
          command = "#{@settings[:wrk_binary]} -t#{@settings[:wrk_concurrency]} -c#{@settings[:wrk_connections]} -d#{@settings[:"#{mode}_seconds"]}s -s#{wrk_script_location} #{wrk_close_header_opts} --latency #{@settings[:url]}"
          puts "Running command: #{command}"
          ret = system(command, out: "#{mode}_output_#{@settings[:timestamp]}.txt")
          raise "Couldn't run #{mode} iterations!" unless ret
        end

        # Warmup iterations first, if there are any
        if @settings[:warmup_seconds] > 0
          verbose "Starting warmup iterations"
          wrk_command.call(:warmup)
        else
          verbose "No warmup iterations..."
        end

        verbose "Starting real benchmark iterations"
        wrk_command.call(:benchmark)
      end

      if !@settings[:no_check_url] && server_env.url_available?
        raise "URL #{@settings[:url].inspect} should not be available after the kill command (#{@settings[:server_kill_matcher].inspect})!"
      end

      # Read wrk's output, parse into our own output array
      if @settings[:warmup_seconds] > 0
        output["requests"]["warmup"] = parse_wrk_into_stats(File.read "warmup_output_#{@settings[:timestamp]}.txt")
        File.unlink "warmup_output_#{@settings[:timestamp]}.txt"
      end
      output["requests"]["benchmark"] = parse_wrk_into_stats(File.read "benchmark_output_#{@settings[:timestamp]}.txt")

      File.unlink "benchmark_output_#{@settings[:timestamp]}.txt"

      json_text = JSON.pretty_generate(output)
      File.open(@settings[:out_file], "w") do |f|
        f.write json_text
      end

      verbose "Wrote data file successfully: #{@settings[:out_file].inspect}"
    end

  end

  module OptionsBuilder
    FRAMEWORKS = [ :rack, :rails ]
    APP_SERVERS = [ :webrick, :puma, :thin, :unicorn, :passenger ]

    def options_by_framework_and_server(framework, server, processes: 1, threads: 1)
      raise "No such framework as #{framework.inspect} (only :rails and :rack)!" unless FRAMEWORKS.include?(framework)
      raise "No such app server as #{server.inspect} (options: #{APP_SERVERS.inspect})!" unless APP_SERVERS.include?(server)

      # This is okay (only) because we've already validated that
      # framework and server are one of a short list of known items.
      method_name = "#{server}_#{framework}_options"

      send(method_name, processes: processes, threads: threads)
    end

    # This generates a temporary configuration file, using the Tmpfile API, which can
    # be used for an application server like Unicorn that may require its configuration
    # be from a file.
    def temp_config_file(contents)
      t = Tmpfile.new("RSB_config_#{Process.pid}_")
      t.to_s
    end

    def webrick_rails_options(processes: 1, threads: 1)
      if processes > 1
        raise "WEBrick doesn't support multiple processes!"
      end
      if threads > 1
        raise "WEBrick supports multiple threads, but not with Rails (see https://github.com/rails/rails/issues/10772)"
      end

      {
        # Benchmarking options
        out_file: File.expand_path(File.join(__dir__, "data", "rsb_rails_TIMESTAMP.json")),

        # Server environment options
        server_cmd: "bundle exec rails server -p PORT",
        server_pre_cmd: "bundle exec rake db:migrate",
        server_kill_matcher: "rails server",
      }
    end

    def webrick_rack_options(processes: 1, threads: 1)
      if processes > 1
        raise "WEBrick doesn't support multiple processes!"
      end
      if threads > 1
        raise "WEBrick supports multiple threads, but RSB doesn't support that yet"
      end

      {
        # Benchmarking options
        out_file: File.expand_path(File.join(__dir__, "data", "rsb_rack_TIMESTAMP.json")),

        # Server environment options
        server_cmd: "bundle exec rackup -p PORT",
        server_kill_matcher: "rackup",
      }
    end

    def unicorn_rails_options(processes: 1, threads: 1)
      if threads > 1
        raise "Unicorn doesn't support multiple threads!"
      end

      cf = temp_config_file(<<UNICORN_CONFIG)
worker_processes #{processes}
# preload_app true
UNICORN_CONFIG
      {
        # Benchmarking options
        out_file: File.expand_path(File.join(__dir__, "data", "rsb_rails_TIMESTAMP.json")),

        # Server environment options
        server_cmd: "bundle exec unicorn -p PORT --config-file #{cf}",
        server_pre_cmd: "bundle exec rake db:migrate",
        server_kill_matcher: "unicorn",

        extra_gems: [
          [ "unicorn", "5.5.1"],
        ],
      }
    end

    def unicorn_rack_options(processes: 1, threads: 1)
      if threads > 1
        raise "Unicorn doesn't support multiple threads!"
      end

      cf = temp_config_file(<<UNICORN_CONFIG)
worker_processes #{processes}
# preload_app true
UNICORN_CONFIG
      {
        # Benchmarking options
        out_file: File.expand_path(File.join(__dir__, "data", "rsb_rack_TIMESTAMP.json")),

        # Server environment options
        server_cmd: "bundle exec unicorn -p PORT --config-file #{cf}",
        server_kill_matcher: "rackup",

        extra_gems: [
          [ "unicorn", "5.5.1"],
        ],
      }
    end

    def thin_rails_options(processes: 1, threads: 1)
      if processes > 1
        raise "Thin doesn't support multiple processes!"
      end
      concurrency_options = threads > 1 ? "--threaded --thread-pool-size #{threads}" : ""

      {
        # Benchmarking options
        out_file: File.expand_path(File.join(__dir__, "data", "rsb_rails_TIMESTAMP.json")),

        # Server environment options
        server_cmd: "bundle exec thin -p PORT --tag rsb-thin-#{Process.pid} #{concurrency_options}",
        server_pre_cmd: "bundle exec rake db:migrate",
        server_kill_matcher: "rsb-thin-#{Process.pid}",

        extra_gems: [
          [ "thin", "1.7.2"],
        ],
      }
    end

    def thin_rack_options(processes: 1, threads: 1)
      if processes > 1
        raise "Thin doesn't support multiple threads!"
      end
      concurrency_options = threads > 1 ? "--threaded --thread-pool-size #{threads}" : ""

      {
        # Benchmarking options
        out_file: File.expand_path(File.join(__dir__, "data", "rsb_rack_TIMESTAMP.json")),

        # Server environment options
        server_cmd: "bundle exec thin -p PORT --tag rsb-thin-#{Process.pid} #{concurrency_options}",
        server_kill_matcher: "rsb-thin-#{Process.pid}",

        extra_gems: [
          [ "thin", "1.7.2"],
        ],
      }
    end

    def puma_rails_options(processes: 1, threads: 1)
      worker_opts = processes > 1 ? "-w #{processes}" : ""

      if processes > 1 && RUBY_PLATFORM == "java"
        raise "Puma's worker mode isn't supported in JRuby, which can't fork processes!"
      end

      {
        # Benchmarking options
        out_file: File.expand_path(File.join(__dir__, "data", "rsb_rails_TIMESTAMP.json")),

        # Server environment options
        server_cmd: "bundle exec puma -p PORT -t #{threads}:#{threads} #{worker_opts} --tag puma_rsb_rails_#{Process.pid}",
        server_pre_cmd: "bundle exec rake db:migrate",
        server_kill_matcher: "puma_rsb_rails_#{Process.pid}",

        extra_gems: [
          [ "puma", "3.12.1"],
        ],
      }
    end

    def puma_rack_options(processes: 1, threads: 1)
      worker_opts = processes > 1 ? "-w #{processes}" : ""

      if processes > 1 && RUBY_PLATFORM == "java"
        raise "Puma's worker mode isn't supported in JRuby, which can't fork processes!"
      end

      {
        # Benchmarking options
        out_file: File.expand_path(File.join(__dir__, "data", "rsb_rack_TIMESTAMP.json")),

        # Server environment options
        server_cmd: "bundle exec puma -p PORT -t #{threads}:#{threads} #{worker_opts} --tag puma_rsb_rack_#{Process.pid}",
        server_kill_matcher: "puma_rsb_rack_#{Process.pid}",

        extra_gems: [
          [ "puma", "3.12.1"],
        ],
      }
    end

    def passenger_rails_options(processes: 1, threads: 1)
      if threads > 1
        raise "Free (non-Enterprise) Passenger doesn't support multiple threads per process!"
      end

      {
        # Benchmarking options
        out_file: File.expand_path(File.join(__dir__, "data", "rsb_rails_TIMESTAMP.json")),

        # Server environment options
        server_cmd: "bundle exec passenger start -p PORT --log-level 2 --max-pool-size #{processes} --min-instances #{processes} --engine=builtin --passenger-pre-start",
        server_pre_cmd: "bundle exec rake db:migrate",
        server_kill_command: "bundle exec passenger stop -p PORT",

        # Extra Gemfile, specified by an environment variable (see Gemfile.common)
        extra_env: {
          "RSB_EXTRA_GEMFILES" => "Gemfile.passenger",
        }
      }
    end

    def passenger_rack_options(processes: 1, threads: 1)
      if threads > 1
        raise "Free (non-Enterprise) Passenger doesn't support multiple threads per process!"
      end

      {
        # Benchmarking options
        out_file: File.expand_path(File.join(__dir__, "data", "rsb_rack_TIMESTAMP.json")),

        # Server environment options
        server_cmd: "bundle exec passenger start -p PORT --log-level 2 --max-pool-size #{processes} --min-instances #{processes} --engine=builtin --passenger-pre-start",
        server_kill_command: "bundle exec passenger stop -p PORT",

        # Extra Gemfile, specified by an environment variable (see Gemfile.common)
        extra_env: {
          "RSB_EXTRA_GEMFILES" => "Gemfile.passenger",
        }
      }
    end
  end

  def check_legal_keys_in_hash(legal_keys, hash, err_msg)
    illegal_keys = hash.keys - legal_keys
    unless illegal_keys.empty?
      raise "#{err_msg} - Unknown items: #{illegal_keys.inspect}!"
    end
  end

  def check_legal_strings_in_array(legal_strings, array, err_msg)
    illegal_strings = array - legal_strings
    unless illegal_strings.empty?
      raise "#{err_msg} - Unknown items: #{illegal_strings.inspect}!"
    end
  end

  # This takes N arrays and returns every combination of
  # one element from each array.
  def combination_set(arrays)
    return [] if arrays.empty?

    # An array of N alternatives, but only one set, e.g. [[ "a", "b" ]]
    return arrays[0].map { |item| [item] } if arrays.size == 1

    outer = arrays[0]
    smaller = combination_set arrays[1..-1]

    #smaller.flat_map { |rest| outer.map { |item| [item, *rest] } }

    outer.flat_map { |item| smaller.map { |rest| [ item ] + rest } }
  end

  module GemfileGenerator
    # This list is a bit optimistic
    RUBY_TYPES = [ :cruby, :jruby, :truffleruby ]

    def gemfile_contents(ruby_version, ruby_type, framework, extras)
      send("#{ruby_type}_#{framework}_gemfile_contents", ruby_version, extras: extras)
    end

    def parse_cruby_version(cruby_version)
      raise "No support for CRuby major versions other than 2!" if cruby_version[0..1] != "2."

      if cruby_version =~ /^(\d)\.(\d)\.(\d+)\-?(p[\d]+)?(pre(.*))$/
        major = $1
        minor = $1.to_i
        micro = $2.to_i
        patch = $3
        pre = $5
      else
        raise "Unexpected Ruby version format: #{cruby_version.inspect}"
      end

      raise "No support for Ruby versions outside 2.0 through 2.7!" unless [0..7].include?(minor)
      [ major, minor, micro, patch, pre ]
    end

    def cruby_rails_gemfile_contents(ruby_version, extras: [])
      major, minor, micro, _ = parse_cruby_version(ruby_version)
      extra_gems = ""
      extra_gems += 'gem "psych", "= 2.2.4"' + "\n" if minor == 0
      extras.each do |row|
        g, ver, constraint = *row
        constraint ||= "= #{ver}" # No constraint? Require it exactly.
        extra_gems += "gem \"#{g}\", \"#{constraint}\"\n"
      end

      return <<GEMFILE
ruby "#{major}.#{minor}.#{micro}"
#{extra_gems}

eval_gemfile "Gemfile.common"
GEMFILE
    end

    alias cruby_rack_gemfile_contents cruby_rails_gemfile_contents

    def jruby_rails_gemfile_contents(ruby_version)
      raise "Currently, there is only JRuby 9.2.X.Y support!" unless ruby_version[0..3] == "9.2."

      return <<GEMFILE
ruby "2.5.0"

eval_gemfile "Gemfile.common"
GEMFILE
    end

    alias jruby_rack_gemfile_contents jruby_rails_gemfile_contents

    def truffleruby_rails_gemfile_contents(ruby_version)
      raise "No TruffleRuby support (yet)"
    end

    def cruby_rails_gemfile_lock_contents(ruby_version, extra_gems: [])
      major, minor, micro, patch, _ = parse_cruby_version ruby_version

      extra_deps  = ""
      extra_specs = ""
      if minor == 0
        extra_deps  += "    psych (2.2.4)\n"
        extra_specs += "  psych (= 2.2.4)\n"
      end
      extra_gems.each do |row|
        g, ver, constraint = *row
        constraint ||= "= #{ver}"  # No constraint? List it as exact version
        extra_specs += "    #{g} (#{ver})"
        extra_deps += "  #{g} (#{constraint})\n"
      end

      return <<GEMFILE_LOCK
GEM
  remote: https://rubygems.org/
  specs:
    actionmailer (4.2.11)
      actionpack (= 4.2.11)
      actionview (= 4.2.11)
      activejob (= 4.2.11)
      mail (~> 2.5, >= 2.5.4)
      rails-dom-testing (~> 1.0, >= 1.0.5)
    actionpack (4.2.11)
      actionview (= 4.2.11)
      activesupport (= 4.2.11)
      rack (~> 1.6)
      rack-test (~> 0.6.2)
      rails-dom-testing (~> 1.0, >= 1.0.5)
      rails-html-sanitizer (~> 1.0, >= 1.0.2)
    actionview (4.2.11)
      activesupport (= 4.2.11)
      builder (~> 3.1)
      erubis (~> 2.7.0)
      rails-dom-testing (~> 1.0, >= 1.0.5)
      rails-html-sanitizer (~> 1.0, >= 1.0.3)
    activejob (4.2.11)
      activesupport (= 4.2.11)
      globalid (>= 0.3.0)
    activemodel (4.2.11)
      activesupport (= 4.2.11)
      builder (~> 3.1)
    activerecord (4.2.11)
      activemodel (= 4.2.11)
      activesupport (= 4.2.11)
      arel (~> 6.0)
    activesupport (4.2.11)
      i18n (~> 0.7)
      minitest (~> 5.1)
      thread_safe (~> 0.3, >= 0.3.4)
      tzinfo (~> 1.1)
    arel (6.0.4)
    binding_of_caller (0.8.0)
      debug_inspector (>= 0.0.1)
    builder (3.2.3)
    byebug (9.0.6)
    coffee-rails (4.1.1)
      coffee-script (>= 2.2.0)
      railties (>= 4.0.0, < 5.1.x)
    coffee-script (2.4.1)
      coffee-script-source
      execjs
    coffee-script-source (1.12.2)
    concurrent-ruby (1.1.3)
    crass (1.0.4)
    debug_inspector (0.0.3)
    erubis (2.7.0)
    execjs (2.7.0)
    ffi (1.9.25)
    globalid (0.4.1)
      activesupport (>= 4.2.0)
    i18n (0.9.5)
      concurrent-ruby (~> 1.0)
    jbuilder (2.8.0)
      activesupport (>= 4.2.0)
      multi_json (>= 1.2)
    jquery-rails (4.3.3)
      rails-dom-testing (>= 1, < 3)
      railties (>= 4.2.0)
      thor (>= 0.14, < 2.0)
    json (1.8.6)
    loofah (2.2.3)
      crass (~> 1.0.2)
      nokogiri (>= 1.5.9)
    mail (2.7.1)
      mini_mime (>= 0.1.1)
    mini_mime (1.0.1)
    mini_portile2 (2.1.0)
    minitest (5.11.3)
    multi_json (1.13.1)
    nokogiri (1.6.8.1)
      mini_portile2 (~> 2.1.0)
    rack (1.6.11)
    rack-test (0.6.3)
      rack (>= 1.0)
    rails (4.2.11)
      actionmailer (= 4.2.11)
      actionpack (= 4.2.11)
      actionview (= 4.2.11)
      activejob (= 4.2.11)
      activemodel (= 4.2.11)
      activerecord (= 4.2.11)
      activesupport (= 4.2.11)
      bundler (>= 1.3.0, < 2.0)
      railties (= 4.2.11)
      sprockets-rails
    rails-deprecated_sanitizer (1.0.3)
      activesupport (>= 4.2.0.alpha)
    rails-dom-testing (1.0.9)
      activesupport (>= 4.2.0, < 5.0)
      nokogiri (~> 1.6)
      rails-deprecated_sanitizer (>= 1.0.1)
    rails-html-sanitizer (1.0.4)
      loofah (~> 2.2, >= 2.2.2)
    railties (4.2.11)
      actionpack (= 4.2.11)
      activesupport (= 4.2.11)
      rake (>= 0.8.7)
      thor (>= 0.18.1, < 2.0)
    rake (12.3.1)
    rb-fsevent (0.10.3)
    rb-inotify (0.9.10)
      ffi (>= 0.5.0, < 2)
    rdoc (4.3.0)
    sass (3.7.2)
      sass-listen (~> 4.0.0)
    sass-listen (4.0.0)
      rb-fsevent (~> 0.9, >= 0.9.4)
      rb-inotify (~> 0.9, >= 0.9.7)
    sass-rails (5.0.7)
      railties (>= 4.0.0, < 6)
      sass (~> 3.1)
      sprockets (>= 2.8, < 4.0)
      sprockets-rails (>= 2.0, < 4.0)
      tilt (>= 1.1, < 3)
    sdoc (0.4.2)
      json (~> 1.7, >= 1.7.7)
      rdoc (~> 4.0)
    spring (2.0.2)
      activesupport (>= 4.2)
    sprockets (3.7.2)
      concurrent-ruby (~> 1.0)
      rack (> 1, < 3)
    sprockets-rails (3.2.1)
      actionpack (>= 4.0)
      activesupport (>= 4.0)
      sprockets (>= 3.0.0)
    sqlite3 (1.3.13)
    thor (0.20.3)
    thread_safe (0.3.6)
    tilt (2.0.9)
    turbolinks (2.5.4)
      coffee-rails
    tzinfo (1.2.5)
      thread_safe (~> 0.1)
    uglifier (4.1.20)
      execjs (>= 0.3.0, < 3)
    web-console (2.3.0)
      activemodel (>= 4.0)
      binding_of_caller (>= 0.7.2)
      railties (>= 4.0)
      sprockets-rails (>= 2.0, < 4.0)
#{extra_specs}

PLATFORMS
  ruby

DEPENDENCIES
  byebug
  coffee-rails (~> 4.1.0)
  jbuilder (~> 2.0)
  jquery-rails
  psych (= 2.2.4)
  rails (= 4.2.11)
  sass-rails (~> 5.0)
  sdoc (~> 0.4.0)
  spring
  sqlite3
  turbolinks (= 2.5.4)
  uglifier (>= 1.3.0)
  web-console (~> 2.0)

RUBY VERSION
   ruby #{major}.#{minor}.#{micro}#{patch}

BUNDLED WITH
   1.17.3
GEMFILE_LOCK
    end

    def cruby_rack_gemfile_lock_contents(ruby_version)
      major, minor, micro, _ = parse_cruby_version ruby_version

      extra_deps = ""
      extra_specs = ""
      if minor == 0
        extra_deps  += "    psych (2.2.4)\n"
        extra_specs += "  psych (= 2.2.4)\n"
      end

      return <<GEMFILE_LOCK
GEM
  remote: https://rubygems.org/
  specs:
#{extra_specs}    rack (1.6.11)
    rake (12.3.2)

PLATFORMS
  ruby

DEPENDENCIES
#{extra_deps}  rack
  rake

RUBY VERSION
   ruby #{major}.#{minor}.#{micro}#{patch}

BUNDLED WITH
   1.17.3
GEMFILE_LOCK
    end

  end
end
