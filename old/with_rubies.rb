# with_rubies.rb
require_relative "bench_lib"
include BenchLib

Dir.chdir(File.expand_path __dir__)

require "tempfile"
require "optparse"
require "json"

no_skip = false

OptionParser.new do |opts|
  opts.banner = <<BANNER
Usage: ruby with_rubies.rb [options] [rubies] [command]
"Rubies" can be "-" for default list, or a comma-separated list of RVM names.
BANNER
  opts.on("-ns", "--no-skip", "Try each Ruby even if it's not in 'rvm list'") do
    no_skip = true
  end
  #opts.on("-w", "--warmup-iterations NUMBER", "number of warmup iterations") do |n|
  #  warmup_iters = n.to_i
  #end
  #opts.on("-n", "--num-iterations", "number of benchmarked iterations") do |n|
  #  benchmark_iters = n.to_i
  #end
  #opts.on("-p", "--port", "port number for Rails server") do |p|
  #  port = p.to_i
  #end
  #opts.on("-o", "--output STRING", "output filename") do |p|
  #  out_file = p
  #end
end

if ARGV.size != 2
    raise "Wrong number of non-option arguments to with_rubies, #{ARGV.size} instead of 2!"
end

rubies, command = *ARGV

DEFAULT_RUBIES = ["2.0.0-p0", "2.0.0-p648", "2.1.10", "2.2.10", "2.3.8", "2.4.5", "2.5.3"]

available = `rvm list strings`
if available.strip == ""
    raise "Can't get list of available rubies!"
end
available_rubies = available.strip.split("\n")

RUBIES.each do |ruby_info|
    raise "Internal error: ruby entry has no name! #{ruby_info.inspect}" unless ruby_info[:name]
end

VERBOSE=true

RUBIES.each do |ruby_info|
    if available_rubies.include?(ruby_info[:rvm])
        puts "RVM list includes #{ruby_info[:rvm].inspect} - running script..."
    else
        puts "RVM list does not include #{ruby_info[:rvm].inspect} - skipping!"
        next
    end

end
