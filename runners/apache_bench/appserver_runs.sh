#!/bin/bash -l

set -e
set -x

export AB_BENCH=${AB_BENCH:-../../ab_bench.rb}

# Pick a concurrency level here
export CONCURRENCY=${CONCURRENCY:-1}

for RSB_RUBY_VERSION in 2.0.0-p0 2.0.0-p648 2.1.10 2.2.10 2.3.8 2.4.5 2.5.3 2.6.0
do
  rvm use $RSB_RUBY_VERSION
  echo "Using Ruby: $RSB_RUBY_VERSION"

  export BUNDLE_GEMFILE="Gemfile.$RSB_RUBY_VERSION"
  export RAILS_ENV=production
  export RACK_ENV=production

  # Rails: migrate as precommand, use widget_tracker dir
  cd widget_tracker
  $AB_BENCH --url http://127.0.0.1:PORT/simple_bench/static -n 10000 -w 100 -c $CONCURRENCY --server-command "bundle _1.17.3_ exec rails server -p PORT" --server-pre-command "bundle _1.17.3_ && bundle _1.17.3_ exec rake db:migrate" --server-kill-match "rails server" -o ../data/rsb_rails_TIMESTAMP.json
  cd ..

  # Rack: no precommand, use rack_hello_world dir
  cd rack_hello_world
  $AB_BENCH --url http://127.0.0.1:PORT/simple_bench/static -n 10000 -w 100 -c $CONCURRENCY --server-command "bundle _1.17.3_ exec rackup -p PORT" --server-pre-command "bundle _1.17.3_" --server-kill-match "rackup" -o ../data/rsb_rack_TIMESTAMP.json
  cd ..

  # Now do Puma - killing Rackup won't kill Puma properly
  export RSB_EXTRA_GEMFILES=Gemfile.puma

  cd widget_tracker
  $AB_BENCH --url http://127.0.0.1:PORT/simple_bench/static -n 10000 -w 100 -c $CONCURRENCY --server-command "bundle _1.17.3_ exec rails server -p PORT" --server-pre-command "bundle _1.17.3_ && bundle _1.17.3_ exec rake db:migrate" --server-kill-match "puma" -o ../data/rsb_rails_TIMESTAMP.json
  cd ..

  cd rack_hello_world
  $AB_BENCH --url http://127.0.0.1:PORT/simple_bench/static -n 10000 -w 100 -c $CONCURRENCY --server-command "bundle _1.17.3_ exec rackup -p PORT" --server-pre-command "bundle _1.17.3_" --server-kill-match "puma" -o ../data/rsb_rack_TIMESTAMP.json
  cd ..


  # Passenger
  export RSB_EXTRA_GEMFILES=Gemfile.passenger

  # TODO: add port number to Passenger start command or this can't figure out when the server is available

  cd widget_tracker
  $AB_BENCH --url http://127.0.0.1:PORT/simple_bench/static -n 10000 -w 100 -c $CONCURRENCY --server-command "bundle _1.17.3_ exec passenger start -p PORT --log-file /dev/null" --server-pre-command "bundle _1.17.3_ && bundle exec rake db:migrate" --server-kill-command "bundle _1.17.3_ exec passenger stop -p 4323" -o ../data/rsb_rails_TIMESTAMP.json
  cd ..

  cd rack_hello_world
  $AB_BENCH --url http://127.0.0.1:PORT/simple_bench/static -n 10000 -w 100 -c $CONCURRENCY --server-command "bundle _1.17.3_ exec passenger start -p PORT --log-file /dev/null" --server-pre-command "bundle _1.17.3_" --server-kill-command "bundle _1.17.3_ exec passenger stop -p 4323" -o ../data/rsb_rack_TIMESTAMP.json
  cd ..

  for RSB_APPSERVER in unicorn thin
  do
    export RSB_EXTRA_GEMFILES="Gemfile.$RSB_APPSERVER"

    cd widget_tracker
    $AB_BENCH --url http://127.0.0.1:PORT/simple_bench/static -n 10000 -w 100 -c $CONCURRENCY --server-command "bundle _1.17.3_ exec rails server -p PORT" --server-pre-command "bundle _1.17.3_ && bundle _1.17.3_ exec rake db:migrate" --server-kill-match "rails server" -o ../data/rsb_rails_TIMESTAMP.json
    cd ..

    cd rack_hello_world
    $AB_BENCH --url http://127.0.0.1:PORT/simple_bench/static -n 10000 -w 100 -c $CONCURRENCY --server-command "bundle _1.17.3_ exec rackup -p PORT" --server-pre-command "bundle _1.17.3_" --server-kill-match "rackup" -o ../data/rsb_rack_TIMESTAMP.json
    cd ..
  done

  unset BUNDLE_GEMFILE
  unset RAILS_ENV
  unset RACK_ENV
  unset RSB_EXTRA_GEMFILES
done