#!/usr/bin/env ruby

# Simple example runner script, editable for different uses; this doesn't specialize on RSB's parameters particularly.
# It's good if you want to test based on something RSB does *not* make particularly straightforward but you can do
# easily in the shell.

RUBIES = [
  "2.6.0",
  "2.6.5",
  "ext-mri-head",
]

TESTS = [
  "gem install bundler -v 1.17.3 && bundle _1.17.3_ && bundle _1.17.3_ exec ./runners/current_ruby.rb",
]

TIMES = 5

# Checked system - error if the command fails
def csystem(cmd, err, opts = {})
  cmd = "bash -l -c \"#{cmd}\"" if opts[:bash] || opts["bash"]
  print "Running command: #{cmd.inspect}\n" if opts[:to_console] || opts["to_console"] || opts[:debug] || opts["debug"]
  if opts[:to_console] || opts["to_console"]
    system(cmd, out: $stdout, err: :out)
  else
    out = `#{cmd}`
  end
  unless $?.success? || opts[:fail_ok] || opts["fail_ok"]
    puts "Error running command:\n#{cmd.inspect}"
    puts "Output:\n#{out}\n=====" if out
    raise err
  end
end

commands = []
RUBIES.each do |ruby|
  TESTS.each_with_index do |test, test_index|
    invocation = "rvm use #{ruby} && export RSB_TEST_INDEX=#{test_index} && #{test}"
    commands.concat([invocation] * TIMES)
  end
end

rand_commands = commands.sample(commands.size)

rand_commands.each do |command|
  csystem(command, "Error running test!", bash: true, to_console: true)
end
