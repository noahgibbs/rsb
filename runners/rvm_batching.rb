#!/usr/bin/env ruby

# This Ruby-based runner shows how to set up a lot of different configurations
# to be run in a large batch. The idea is that many different configurations
# can be specified and then run in a random order to reduce the effect of
# time correlation (e.g. background processes, transient network events.)

# The runner accepts a JSON file containing the test configurations and
# runs the batches in a random order. (TODO: also accept a data directory
# to continue a run after interruption or crashes)

# This is also an example of a runner that is error-tolerant but
# error-aware. That's not a good default for every case, but it can be
# very useful for large batches and long benchmarking sessions. If you're assuming
# random ordering reduces time-based correlation, keep in mind that
# a misconfiguration that changes the ordering can reduce or eliminate
# that benefit - if all your JRuby batches fail the first time and are
# re-run, then they aren't alternated with your other configurations.

# JSON Configuration Format:

# Configuration keys with multiple values (e.g. ruby, framework, app_server) will
# result in the specified number of batches in *each* configuration. So specifying
# ten batches for six Rubies, two frameworks and three app_servers will result in
# 10 * 6 * 2 * 3 = 360 batches of the specified duration, plus setup and warmup time.
# This can rapidly grow to be a large number.

# A configuration must, at a minimum, specify a Ruby version.

# Runner settings:
#
# * version: if present, must be 1
# * random_seed: if present, must be an integer; controls batch ordering
# * fail_on_error: if present and true, fail when a batch fails; otherwise continue on error

# Configuration settings in each configuration (hash) in the config array:
#
# * batches: number of batches in this/these configuration(s).
# * ruby: one or more Ruby versions to test; must be in a format recognized by "rvm use"
# * framework: may be one or both of "rack", "rails"
# * duration: number of seconds to run the "real" benchmark iterations
# * warmup: number of seconds to run the warmup iterations that don't count in the final time
# * url: url to test; default is http://127.0.0.1:PORT/static
# * app_server: what app server to use, such as puma, webrick or unicorn
# * processes: number of processes to use for the server - numbers > 1 may not be compatible with some app servers
# * threads: number of threads to use for the server - numbers > 1 may not be compatible with some app servers
# * wrk: settings for the wrk load tester: "connections", "threads", "binary", "script_location"
# * rack_env: value to use for RACK_ENV and RAILS_ENV
# * gemfile: if "static", use an existing Gemfile.(version).lock. If "dynamic", try to generate one. Default: "static"
# * debug_server: send server console output to your own console instead
#   of suppressing it.
# * close_connection: turn off KeepAlive server-side for servers that have
#   KeepAlive bugs.
# * batch_retry: if specified as true, check files in output directory and only add new
#   files as needed to complete one full configuration as specified.
# * out_dir: by default, "data". Directory for output of batch data.
#
# * threads and processes can be specified for app servers that support them. However,
#   you may need multiple configurations if you're using multiple app servers with
#   different thread or process capabilities -- to specify 8 processes to Unicorn
#   vs 8 threads to Thin, you'll need multiple configurations.

# {
#   runner: {
#     "# keys starting with pound sign are comments": "and their values are ignored",
#     version: 1,
#     random_seed: 7523534,  # sets batch ordering, assuming no recovery/restarts
#     fail_on_error: true    # if true, fail when an error occurs; default: false
#   },
#   configurations: [
#     {
#       batches: 10,
#       ruby: [ "2.6.0", "jruby-9.2.5.0" ],
#       framework: [ "rails", "rack" ],
#       duration: 120, # in seconds
#       warmup: 15, # in seconds, 0 for no warmups
#       rack_env: "production",
#       wrk: {
#         "# wrk settings": "connections is the actual concurrency, threads is # of reactor threads",
#         connections: 15,
#         threads: 1
#       },
#       url: "http://127.0.0.1:PORT/static",
#       app_server: [ "puma", "webrick" ],
#       processes: 4,
#       threads: 4,
#       close_connection: true,
#       debug_server: false
#     },
#     {
#       "# configs with no non-comment keys are ignored": "to ease programmatic generation"
#     }
#   ]
# }

require_relative "../bench_lib"
include BenchLib
include BenchLib::OptionsBuilder
include BenchLib::GemfileGenerator

require "json"

def remove_json_comments!(obj)
  return unless obj.respond_to?(:each)
  if obj.is_a?(Hash)
    obj.delete_if { |k, v| k[0] == "#" }
    obj.values.each { |v| remove_json_comments!(v) }
  else
    obj.each { |item| remove_json_comments!(item) }
  end
end

# This method takes an options hash where some values are
# arrays of alternatives, and the "batches" key is an integer.
# It creates an array of hashes where
# each is one combination of those alternatives, repeated a
# number of times equal to the batches. If there are,
# say, four array-valued fields of size 6, 2 and 4 with
# batches set to 10, this method will
# return an array of 10 * 6 * 2 * 4 = 480 options hashes.
#
# This is not a terribly efficient implementation. Though
# we're going to have to do a (probably multi-minute)
# benchmark run for every hash returned, so this shouldn't
# be a big drag on the runtime.
def get_runs_from_options(opts)
  keys = opts.keys - [:batches] # Batches does a different, hardcoded thing
  multi_keys = keys.select { |k| opts[k].is_a?(Array) }
  ps_multi = combination_set(multi_keys.map { |mk| opts[mk] })

  (1..opts[:batches]).flat_map do |batch_idx|
    ps_multi.flat_map do |opts_chosen|
      chosen_hash = {}
      multi_keys.each_with_index { |k, idx| chosen_hash[k] = opts_chosen[idx] }
      #chosen_hash = Hash[multi_keys.zip(opts_chosen)]
      opts.merge(chosen_hash).merge(:batch_index => batch_idx)
    end
  end
end

KNOWN_TOPLEVEL_KEYS = [
  "runner", "configurations",
]
KNOWN_RUNNER_KEYS = [
  "version", "random_seed",
]
KNOWN_CONFIG_KEYS = [
  "ruby", "framework", "batches", "duration", "warmup", "wrk", "url", "app_server",
  "processes", "threads", "debug_server", "close_connection", "rack_env", "extra_env",
  "gemfile", "override",
]
KNOWN_OVERRIDE_KEYS = [
  "server_cmd", "port",
]

if ARGV.size != 1
  STDERR.puts "Please specify exactly one JSON configuration file as the only argument."
  exit -1
end

config = JSON.load File.read(ARGV[0])
remove_json_comments! config
check_legal_keys_in_hash KNOWN_TOPLEVEL_KEYS, config, "Unknown top-level field names"
if config["runner"]
  check_legal_keys_in_hash KNOWN_RUNNER_KEYS, config["runner"], "Unknown field names in 'runner'"
end

config["configurations"].select! { |conf| !conf.empty? }

num_configs = config["configurations"].size
if num_configs == 0
  raise "No non-empty configurations found in #{ARGV[0]}!"
end

config["configurations"].each_with_index do |conf, index|
  check_legal_keys_in_hash KNOWN_CONFIG_KEYS, conf, "Unknown field names in configuration \##{index}/#{num_configs}"
  if conf["override"]
    check_legal_keys_in_hash KNOWN_OVERRIDE_KEYS, conf["override"], "Unknown override key(s) in configuration \##{index}/#{num_configs}"
  end
end

if config["runner"]["version"] && config["runner"]["version"] != 1
  raise "Error! Unknown version #{config["runner"]["version"].inspect} instead of 1!"
end

random_seed = config["runner"]["random_seed"] ? config["runner"]["random_seed"] : Time.now.to_i
runs = []

FAIL_ON_ERROR = config["runner"]["fail_on_error"] || false

config["configurations"].each do |conf|
  unless conf["ruby"]
    raise "Every configuration must specify at least one Ruby version!"
  end
  conf["wrk"] ||= {}  # Doesn't exist? Add it, but empty.
  # This opts array is similar to, but slightly different from, the one that BenchmarkLib
  # takes for running a single batch.
  opts = {
    batches: conf["batches"] || 1,

    wrk_binary: conf["wrk"]["binary"] || "wrk",
    wrk_concurrency: conf["wrk"]["threads"] || 1,
    wrk_connections: conf["wrk"]["connections"] || 5,
    wrk_close_connection: conf["close_connection"] ? conf["close_connection"] : false,
    wrk_script_location: conf["wrk"]["script_location"] ? conf["wrk"]["script_location"] : "./final_report.lua",

    warmup_seconds: conf["warmup"] ? conf["warmup"] : 15,
    benchmark_seconds: conf["duration"] ? conf["duration"] : 120,

    rack_env: conf["rack_env"] || "production",
    bundler_version: conf["bundler_version"] || "1.17.3",
    extra_env: conf["extra_env"] || {},
    server_ruby_opts: conf["ruby_opts"] ? conf["ruby_opts"] : nil,

    url: conf["url"] || "http://127.0.0.1:PORT/static",

    suppress_server_output: conf["debug_server"] ? !conf["debug_server"] : true,

    # This set of options interact in an interesting and complicated way with
    # the underlying options - "framework" is basically an abstraction on top
    # of the raw commands to start the server, for instance. And "ruby"
    # turns into an rvm command that runs in the child process.
    framework: [conf["framework"]].flatten(1).map(&:to_sym) || [:rails, :rack],
    app_server: conf["app_server"] ? [conf["app_server"]].flatten(1).map(&:to_sym) : [:puma],
    processes: conf["processes"] || 1,
    threads: conf["threads"] || 1,
    ruby: [conf["ruby"]].flatten(1),
  }
  check_legal_strings_in_array BenchLib::OptionsBuilder::APP_SERVERS, opts[:app_server], "Unexpected app server name(s)"
  check_legal_strings_in_array BenchLib::OptionsBuilder::FRAMEWORKS, opts[:framework], "Unexpected framework name(s)"

  # Any overrides?
  if conf["override"]
    opts[:override] ||= {}
    KNOWN_OVERRIDE_KEYS.each do |key|
      opts[:override][key.to_sym] = conf["override"][key] if conf["override"][key]
    end
  end

  opt_runs = get_runs_from_options(opts)

  runs.concat opt_runs
end

# Randomize the order of the runs.
# A random seed can allow repeatability, which is normally only for debugging heisenbugs.
# But I'll print it out in case you get a weird bad run and need to make it happen again.
puts "Random seed: #{random_seed}"
srand(random_seed)
runs = runs.sample(runs.size)

# Keep track of information as the runs complete
COUNTERS = {
  runs: 0,
  runs_success: 0,
  runs_failure: 0,
  runs_errors: 0,
}

def run_benchmark(orig_opts)
  extra_env = orig_opts.delete(:extra_env) || {}  # Have to merge after getting app_server env vars
  rr_opts = options_by_framework_and_server(orig_opts[:framework], orig_opts[:app_server], processes: orig_opts[:processes], threads: orig_opts[:threads])
  extra_gems = rr_opts.delete(:extra_gems) || []

  bench_dir = "#{orig_opts[:framework]}_test_app"

  bundle_gemfile = nil
  case orig_opts[:gemfile]
  when NilClass, "dynamic"
    # Write out Gemfile.dynamic
    File.open("#{bench_dir}/Gemfile.dynamic", "w") do |f|
      f.write(gemfile_contents(orig_opts[:ruby], :cruby, orig_opts[:framework], extra_gems))
    end
    bundle_gemfile = "Gemfile.dynamic"
  when String
    bundle_gemfile = "#{bench_dir}/#{orig_opts[:gemfile]}"
    unless File.exist?(bundle_gemfile)
      raise "Supplied Gemfile path does not exist for this framework: #{bundle_gemfile.inspect}!"
    end
  else
    raise "Unrecognized value for \"gemfile\" option: #{orig_opts[:gemfile].inspect}!"
  end

  opts = rr_opts.merge({
    # Wrk settings
    wrk_binary: orig_opts[:wrk_binary] || "wrk",
    wrk_concurrency: orig_opts[:wrk_concurrency],  # This is wrk's own "concurrency" setting for number of requests in flight
    wrk_connections: orig_opts[:wrk_connections],  # Number of connections for wrk to create and use
    wrk_close_connection: orig_opts[:wrk_close_connection],
    warmup_seconds: orig_opts[:warmup_seconds],
    benchmark_seconds: orig_opts[:benchmark_seconds],
    url: orig_opts[:url],

    # Bundler/Rack/Gem/Env config
    bundler_version: orig_opts[:bundler_version],

    :verbose => 1,

    before_worker_cmd: "rvm use #{orig_opts[:ruby]} && #{SETTINGS_DEFAULTS[:before_worker_cmd]}",  # Run before each batch
    bundle_gemfile: bundle_gemfile,
    rack_env: orig_opts[:rack_env],

    # Useful for debugging, annoying for day-to-day use
    suppress_server_output: orig_opts[:suppress_server_output],
  })
  opts[:extra_env] ||= {}
  opts[:extra_env].merge!(extra_env) # This will take precedence field-by-field, but not overwrite the hash completely

  # Can't include this in the merge above or it'll overwrite Puma's extra_env
  opts[:extra_env]["RSB_RUN_INDEX"] = orig_opts[:batch_index]

  # Overrides *after* the normal options...
  if orig_opts[:override]
    KNOWN_OVERRIDE_KEYS.map(&:to_sym).each do |field|
      opts[field] = orig_opts[:override][field] if orig_opts[:override][field]
    end
  end

  begin
    COUNTERS[:runs] += 1
    env = nil # Set scope for this local

    Dir.chdir(bench_dir) do
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
    puts "Caught exception in #{orig_opts[:framework]} app: #{exc.message.inspect}"
    puts "Backtrace:\n#{exc.backtrace.join("\n")}"
    if FAIL_ON_ERROR
      STDERR.puts "Failing on error, as requested."
      exit -1
    else
      puts "#{orig_opts[:framework].to_s.capitalize} app for Ruby #{orig_opts[:ruby].inspect} failed, but we'll keep going..."
    end
  end
end

# Now for every random-ordered run, make it happen.
runs.each do |opts|
  run_benchmark(opts)
end

print "\n\n===================\n"
puts "#{COUNTERS[:runs]} total runs"
puts "#{COUNTERS[:runs_failure]} generated exceptions and/or produced no data file, and so did not complete successfully"
puts "#{COUNTERS[:runs_errors]} completed with data but had high error rates"

puts "#{COUNTERS[:runs_success] - COUNTERS[:runs_errors]}/#{COUNTERS[:runs]} completed successfully w/o high error rate"
