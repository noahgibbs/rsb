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

## TODO

* Set up SQLite in-memory database
* Composite routes based on Discourse and CodeTriage
