#!/usr/bin/env ruby

# Similar to current_ruby.rb, but options are passed from the command line.
# See #BenchLib::SETTINGS_DEFAULTS for documentation about the options.

require 'optparse'

require_relative "../bench_lib"
include BenchLib
include BenchLib::OptionsBuilder

overrides = {
  wrk_close_connection: true,
  url: "http://127.0.0.1:PORT/static",
  bundle_gemfile: "Gemfile.#{RUBY_VERSION}",
  suppress_server_output: false,
}
defaults = BenchLib::SETTINGS_DEFAULTS.merge(overrides)

options = overrides.dup
opt_parser = OptionParser.new(<<HELP, 44) do |opts|
Usage: #{__FILE__} [options] APP SERVER
  APP: #{FRAMEWORKS.join(', ')}
  SERVER: #{APP_SERVERS.join(', ')}
HELP

  defaults.each_pair do |name, default_value|
    type = default_value == nil ? String : default_value.class
    type = Integer if type < Integer # For Ruby < 2.4
    optname = name.to_s.tr('_', '-')
    if type == Hash
      # skip
    elsif type == TrueClass || type == FalseClass
      opts.on("--[no-]#{optname}", "Default: #{default_value.inspect}") do |v|
        options[name] = v
      end
    else
      opts.on("--#{optname} #{type.name.upcase}", type, "Default: #{default_value.inspect}") do |v|
        options[name] = v
      end
    end
  end
end

opt_parser.parse!

if ARGV.size == 2
  which_app, server = ARGV.map(&:to_sym)
else
  abort "Must have 2 arguments: APP and SERVER but was #{ARGV.inspect}\n\n#{opt_parser.help}"
end

p options

# Default concurrency
options = options_by_framework_and_server(which_app, server).merge(options)
extra_gems = options.delete(:extra_gems) || [] # Can be used for dynamic Gemfile generation

# Here's the meat of how to turn those options into benchmark output
Dir.chdir("#{which_app}_test_app") do
  BenchmarkEnvironment.new(options).run_wrk
end
