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

## Usage

RSB uses a number of "runner" scripts to test different
configurations. For most uses of RSB, you'll run one. For more
customized uses of RSB, you'll make your own runner script.

## Canonical Configurations

RSB will cheerfully run with whatever concurrency you like. However,
here are some useful configurations to use or test:

* 1 Process, 1 Thread: this gives minimum latency
* N Processes, 1 Thread: high throughput for most workloads; you usually
  want roughly 1 process per core, or 1.3-1.5 processes/core with
  hyperthreaded cores
* 1 Process, N Threads: this is usually best for JVM-based Ruby implementations
  like JRuby or TruffleRuby

## Threads and Concurrency

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

ApacheBench is not recommended for new uses - its reporting and
accuracy are poor and there are bugs and edge-cases that make it hard
to be sure you're getting what you think you are.

For newer use cases, we follow Phusion.nl's recommendation for "wrk",
a simple, powerful and accurate benchmarking program.
