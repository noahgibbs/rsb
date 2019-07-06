# Rails Simpler Bench

Are you looking for a comprehensive, real-world benchmark to show the
performance of a large, highly-concurrent Ruby on Rails application?
You're probably looking for [Rails Ruby
Bench](https://github.com/noahgibbs/rails_ruby_bench). But RRB is
unfortunately large and unwieldy - it's a real-world benchmark with
lots of dependencies and messiness. The easiest way to run it is to
build an AWS image and run it in a dedicated virtual machine. While
RRB does what it can to be repeatable, it has some strong limits due
to concurrency - the behavior of thread interaction can be highly
unpredictable.

As well, RRB is based on Discourse, a real-world production
application. This makes it hard to change Rails (and sometimes Ruby)
versions, and it requires the benchmark to be fairly messy -- it has
to follow the evolution of a real-world solution to real-world
(unrelated to the benchmark) problems.

RRB's strengths and weaknesses are easy to sum up in the same
sentence: it embraces and measures as much real-world complexity as it
reasonably can.

Would you like a much-simplified Ruby on Rails benchmark with fewer
dependencies and more repeatability? Then RSB may be for you.

This benchmark, like Rails Ruby Bench, was written and maintained via
sponsorship from AppFolio (https://engineering.appfolio.com). Thank
you, AppFolio!

## Usage

### Quick Start

There are a small, specific number of Rubies that are already supported (have a Gemfile.lock.) You can see which ones by looking in the rails_test_app or rack_test_app directory - but they include 2.0.0p0, 2.0.0p648, 2.1.0, 2.2.10, 2.3.8, 2.4.5, 2.5.3 and 2.6.0. JRuby 9.2.0.0 is also partially supported - see below in this file for more details.

You can add support for another Ruby by adding a Gemfile for it - see the existing Gemfiles for examples, but they're quite simple.

(Note: there is an experimental branch which allows dynamically generating Gemfiles for any Ruby)

If you want to check the current speed of a benchmark on your current machine, you can do it fairly simply:

```bash
./runners/current_ruby.rb
```

If you want to change settings, you can do it in that runner script.

You can also run with more settings changes and multiple different Rubies if you have RVM installed - see runners/rvm_rubies.rb for a full list of environment variables to set parameters. Here is an example, specifying many of them:

```bash
RSB_NUM_RUNS=10 RSB_RUBIES="2.6.0 2.4.5 2.0.0-p0" RSB_DURATION=180 RSB_WARMUP=20 RSB_FRAMEWORKS=rack RSB_APP_SERVER=puma RSB_PROCESSES=1 RSB_THREADS=1 ./runners/rvm_rubies.rb
```

### Process Structure

* Runner (e.g., `runners/current_ruby.rb`)
  * `ruby wrk_subprocess.rb benchlib.json`
    * Server (e.g., `bundle exec rails server`)
    * `wrk OPTIONS URL`

### Runners

RSB uses a number of "runner" scripts to test different
configurations. For most uses of RSB, you'll run one. For more
customized uses of RSB, you'll make your own runner script.

The file runners/rvm_rubies.rb is the most comprehensive as of this
writing - see the beginning of the file for documentation. It runs
primarily from environment variables.

### Analysis

After the runner completes, you should have a directory of data files,
which can be used directly or analyzed. The file process.rb in the
root directory of this repository performs cohort-based analysis, good
for checking simple A/B questions of the form, "did this change speed
up Ruby or slow it down? By how much?"

For instance, to compare the speed of many different Rubies using a
directory of data files, you can often type something like
"../process.rb -c 'rvm current'", which will use the recorded RVM Ruby
for each batch of data to analyze each Ruby's subset of the data
separately.

### Experiments

The analysis above is okay. You can keep data files in multiple
directories, analyze them separately and compare. But that's not
always a reasonable choice, and often you'd rather do it differently.

The RSB output files record any environment variable containing
"RUBY", "RSB" or "GEM" as relevant. If you want to conduct an
experiment between multiple configurations, it's often a good idea to
set an environment variable starting with RSB so that you can separate
the relevant data files afterward. For instance, if you set
"RSB_MY_EXP_CONFIG=7" beforehand, then that setting would propagate to
the data file since the environment variable contains "RSB".

To group them by the value of that variable afterward, set up cohorts
using that variable. For instance:

```
cd my_data_dir
~/src/rsb/process.rb -c "RUBY_VERSION,env-RSB_MY_EXP_CONFIG"
```

The above example would group the data into cohorts according to which
Ruby version was used and the value of the environment variable
RSB_MY_EXP_CONFIG. You can then compare the latencies, throughputs
or other relevant data.

If for some reason setting an environment variable is inappropriate to
your use case, you'll need to separate the relevant data in some other
way.

### JRuby

JRuby is intended to be a target Ruby configuration for RSB, but not everything is working yet.

Here are some restrictions:

* JRuby can be specified as a *target* configuration, such as in
  RSB_RUBIES in runners/rvm_rubies.rb. However, some of the test
  harness can't run in JRuby because it doesn't have "fork".
  By starting the test harness from a CRuby implementation, you
  can still check JRuby's speed.

* JRuby uses its own SQLite3 adapter. This will give slightly
  different performance than the sqlite3 gem, which isn't
  supported in JRuby.

### Canonical Configurations

RSB will cheerfully run with whatever concurrency you like. However,
here are some useful configurations to use or test:

* 1 Process, 1 Thread: this gives minimum latency
* N Processes, 1 Thread: high throughput for most workloads; you usually
  want roughly 1 process per core, or 1.3-1.5 processes/core with
  hyperthreaded cores
* 1 Process, N Threads: this is usually best for JVM-based Ruby implementations
  like JRuby or TruffleRuby

### Threads and Concurrency

An interesting property of RSB, especially compared to RRB or other large
Rails apps, is that it isn't very threading-friendly on CRuby. The GIL
means that Ruby code can't run concurrently with other Ruby code.
A since RSB doesn't use Reddit or caches at all, or the database much,
that means there's relatively little non-Ruby code.

For instance, with the static route, here are some example route throughputs:

(Format is # of Processes, # of threads, throughput in iters/sec, StdDev)

* 1, 1, 1005  StdDev 11.4
* 1, 2, 873, StdDev 17.1
* 1, 3, 898, StdDev 8.9
* 1, 4, 893, StdDev 5.0
* 4, 1, 3892, StdDev 26.4
* 4, 2, 3009, StdDev 20.7
* 4, 4, 3289, StdDev 28.5
* 4, 6, 3247, StdDev 51.6
* 4, 8, 2901, StdDev 111.2
* 8, 1, 5059, StdDev 118.3
* 8, 2, 4776, StdDev 32.2
* 8, 4, 4936, StdDev 209.7
* 8, 6, 5039, StdDev 105.4
* 8, 8, 5159, StdDev 178.8

Notice that in many cases, increasing the number of threads causes the
throughput to go *downward*? RSB isn't particularly thread-friendly,
especially when not using the database in the measured route.

## Load Testing Tools

ApacheBench is no longer being used for RSB, and any remaining vestiges of it are just that. It doesn't report individual timings below millisecond resolution, its KeepAlive code is HTTP 1.0-only and causes bugs in Puma, and it has trouble with dynamic documents (cases where responses aren't byte-for-byte) identical. After extensive attempts to use it, the accuracy issues have been insurmountable (http://engineering.appfolio.com/appfolio-engineering/2019/1/18/benchmarking-ruby-app-servers-badly).

For newer use cases, we follow Phusion.nl's recommendation for "wrk", a simple, powerful and accurate benchmarking program that avoids reopening connections (Google "ephemeral port exhaustion" for details on why reopening connections gets to be a problem quickly on Linux.)
