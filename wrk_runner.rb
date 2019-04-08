# wrk_runner.rb
# After forking, BenchLib needs to re-exec so that we can have a different Ruby version and
# different configuration.

require "json"
require_relative "./bench_lib"
include BenchLib

settings_file = ARGV[0]
settings = JSON.parse(File.read(settings_file), symbolize_names: true)
be = BenchmarkEnvironment.new settings

be.run_wrk_bench

exit 0 # Return w/o error
