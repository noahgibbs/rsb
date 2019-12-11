#!/usr/bin/env ruby

# Shell-based runner for checking memory compaction's effect.
# Compaction is, as I write this, only available manually and in prerelease 2.7 Rubies.

RUBY_TO_TEST = "2.7.0-preview3"
TEST_DURATION = 10
TEST_WARMUP = 0

TESTS = [
  "RSB_RUBIES=#{RUBY_TO_TEST} RSB_FRAMEWORKS=rails RSB_NUM_RUNS=1 RSB_DURATION=#{TEST_DURATION} RSB_WARMUP=#{TEST_WARMUP} RSB_COMPACT=YES RSB_GET_FINAL_MEM=YES RSB_BUNDLE_GEMFILE=dynamic bundle _1.17.3_ exec runners/rvm_rubies.rb",
  "RSB_RUBIES=#{RUBY_TO_TEST} RSB_FRAMEWORKS=rails RSB_NUM_RUNS=1 RSB_DURATION=#{TEST_DURATION} RSB_WARMUP=#{TEST_WARMUP} RSB_COMPACT=NO RSB_GET_FINAL_MEM=YES RSB_BUNDLE_GEMFILE=dynamic bundle _1.17.3_ exec runners/rvm_rubies.rb",
]

TIMES = 2

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

# Only one Ruby, so we can just install Bundler and gems once, manually.
Dir.chdir("rails_test_app") do
  csystem("rvm use #{RUBY_TO_TEST} && gem install bundler -v 1.17.3 && bundle _1.17.3_", bash: true, to_console: true)
end

commands = []
TESTS.each_with_index do |test, test_index|
  invocation = "RSB_RUBIES=#{RUBY_TO_TEST} RSB_TEST_INDEX=#{test_index} && #{test}"
  commands.concat([invocation] * TIMES)
end

rand_commands = commands.sample(commands.size)

rand_commands.each do |command|
  csystem(command, "Error running test!", bash: true, to_console: true)
end
