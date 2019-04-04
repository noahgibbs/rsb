#!/bin/bash -l

set -e
set -x

export WRK_BENCH=${WRK_BENCH:-../wrk_bench.rb}
export WRK=${WRK:-wrk}

# Pick a benchmark concurrency level here, which is passed to wrk
export CONCURRENCY=${CONCURRENCY:-1}

export RAILS_ENV=${RSB_RACK_ENV:-production}
export RACK_ENV=${RSB_RACK_ENV:-production}

export LOCAL_BUNDLER_VERSION=${RSB_BUNDLER_VERSION:-_1.17.3_}


# Server-Specific tuning
export PASSENGER=${RSB_PASSENGER:-passenger}
export PASSENGER_PROCESSES=${RSB_PASSENGER_PROCESSES:-10}

export PASSENT=${RSB_PASSENT:-/usr/bin/passenger}
export PASSENT_PROCESSES={RSB_PASSENT_PROCESSES:-10}
export PASSENT_THREADS={RSB_PASSENT_THREADS:-6}

# For later Puma tuning
export PUMA_PROCESSES=${RSB_PUMA_PROCESSES:-10}

for RSB_RUBY_VERSION in 2.0.0-p0 2.0.0-p648 2.1.10 2.2.10 2.3.8 2.4.5 2.5.3 2.6.0
do
  rvm use $RSB_RUBY_VERSION
  echo "Using Ruby: $RSB_RUBY_VERSION"

  export BUNDLE_GEMFILE="Gemfile.$RSB_RUBY_VERSION"

  # Rails: migrate as precommand, use widget_tracker dir
  cd widget_tracker
  $WRK_BENCH --wrk-path $WRK --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 -c $CONCURRENCY --server-command "bundle $LOCAL_BUNDLER_VERSION exec rails server -p PORT" --server-pre-command "bundle $LOCAL_BUNDLER_VERSION && bundle $LOCAL_BUNDLER_VERSION exec rake db:migrate" --server-kill-match "rails server" -o ../data/rsb_rails_TIMESTAMP.json
  cd ..

  # Rack: no precommand, use rack_hello_world dir
  cd rack_hello_world
  $WRK_BENCH --wrk-path $WRK --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 -c $CONCURRENCY --server-command "bundle $LOCAL_BUNDLER_VERSION exec rackup -p PORT" --server-pre-command "bundle $LOCAL_BUNDLER_VERSION" --server-kill-match "rackup" -o ../data/rsb_rack_TIMESTAMP.json
  cd ..

  # Now do Puma - killing Rackup won't kill Puma properly
  export RSB_EXTRA_GEMFILES=Gemfile.puma

  cd widget_tracker
  $WRK_BENCH --wrk-path $WRK --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 -c $CONCURRENCY --server-command "bundle $LOCAL_BUNDLER_VERSION exec rails server -p PORT" --server-pre-command "bundle $LOCAL_BUNDLER_VERSION && bundle $LOCAL_BUNDLER_VERSION exec rake db:migrate" --server-kill-match "puma" -o ../data/rsb_rails_TIMESTAMP.json
  cd ..

  cd rack_hello_world
  $WRK_BENCH --wrk-path $WRK --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 -c $CONCURRENCY --server-command "bundle $LOCAL_BUNDLER_VERSION exec rackup -p PORT" --server-pre-command "bundle $LOCAL_BUNDLER_VERSION" --server-kill-match "puma" -o ../data/rsb_rack_TIMESTAMP.json
  cd ..


  # Passenger
  export RSB_EXTRA_GEMFILES=Gemfile.passenger

  cd widget_tracker
  $WRK_BENCH --wrk-path $WRK --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 -c $CONCURRENCY --server-command "bundle $LOCAL_BUNDLER_VERSION exec passenger start -p PORT --log-level 2" --server-pre-command "bundle $LOCAL_BUNDLER_VERSION && bundle exec rake db:migrate" --server-kill-command "bundle $LOCAL_BUNDLER_VERSION exec passenger stop -p 4323" -o ../data/rsb_rails_TIMESTAMP.json
  cd ..

  cd rack_hello_world
  $WRK_BENCH --wrk-path $WRK --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 -c $CONCURRENCY --server-command "bundle $LOCAL_BUNDLER_VERSION exec passenger start -p PORT --log-level 2" --server-pre-command "bundle $LOCAL_BUNDLER_VERSION" --server-kill-command "bundle $LOCAL_BUNDLER_VERSION exec passenger stop -p 4323" -o ../data/rsb_rack_TIMESTAMP.json
  cd ..

  # Passenger-Tuned
  export RSB_EXTRA_GEMFILES=Gemfile.passenger-tuned

  cd widget_tracker
  $WRK_BENCH --wrk-path $WRK --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 -c $CONCURRENCY --server-command "bundle $LOCAL_BUNDLER_VERSION exec passenger start -p PORT --log-level 2 --max-pool-size $PASSENGER_PROCESSES --min-instances $PASSENGER_PROCESSES --engine=builtin --passenger-pre-start" --server-pre-command "bundle $LOCAL_BUNDLER_VERSION && bundle exec rake db:migrate" --server-kill-command "bundle $LOCAL_BUNDLER_VERSION exec passenger stop -p 4323" -o ../data/rsb_rails_TIMESTAMP.json
  cd ..

  cd rack_hello_world
  $WRK_BENCH --wrk-path $WRK --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 -c $CONCURRENCY --server-command "bundle $LOCAL_BUNDLER_VERSION exec passenger start -p PORT --log-level 2 --max-pool-size $PASSENGER_PROCESSES --min-instances $PASSENGER_PROCESSES --engine=builtin --passenger-pre-start" --server-pre-command "bundle $LOCAL_BUNDLER_VERSION" --server-kill-command "bundle $LOCAL_BUNDLER_VERSION exec passenger stop -p 4323" -o ../data/rsb_rack_TIMESTAMP.json
  cd ..

  # Passenger Enterprise ("passent")
  export RSB_EXTRA_GEMFILES=Gemfile.passent

  if [! -z "$RSB_PASSENT"]
  then
    cd widget_tracker
    $WRK_BENCH --wrk-path $WRK --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 -c $CONCURRENCY --server-command "bundle $LOCAL_BUNDLER_VERSION exec passenger start -p PORT --log-level 2 --max-pool-size $PASSENT_PROCESSES --min-instances $PASSENT_PROCESSES --passenger-concurrency-model thread --passenger-thread-count $PASSENT_THREADS --engine=builtin --passenger-pre-start" --server-pre-command "bundle $LOCAL_BUNDLER_VERSION && bundle exec rake db:migrate" --server-kill-command "bundle $LOCAL_BUNDLER_VERSION exec passenger stop -p 4323" -o ../data/rsb_rails_TIMESTAMP.json
    cd ..

    cd rack_hello_world
    $WRK_BENCH --wrk-path $WRK --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 -c $CONCURRENCY --server-command "bundle $LOCAL_BUNDLER_VERSION exec passenger start -p PORT --log-level 2 --max-pool-size $PASSENGER_PROCESSES --min-instances $PASSENGER_PROCESSES --engine=builtin --passenger-pre-start" --server-pre-command "bundle $LOCAL_BUNDLER_VERSION" --server-kill-command "bundle $LOCAL_BUNDLER_VERSION exec passenger stop -p 4323" -o ../data/rsb_rack_TIMESTAMP.json
    cd ..
  fi

  for RSB_APPSERVER in unicorn thin
  do
    export RSB_EXTRA_GEMFILES="Gemfile.$RSB_APPSERVER"

    cd widget_tracker
    $WRK_BENCH --wrk-path $WRK --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 -c $CONCURRENCY --server-command "bundle $LOCAL_BUNDLER_VERSION exec rails server -p PORT" --server-pre-command "bundle $LOCAL_BUNDLER_VERSION && bundle $LOCAL_BUNDLER_VERSION exec rake db:migrate" --server-kill-match "rails server" -o ../data/rsb_rails_TIMESTAMP.json
    cd ..

    cd rack_hello_world
    $WRK_BENCH --wrk-path $WRK --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 -c $CONCURRENCY --server-command "bundle $LOCAL_BUNDLER_VERSION exec rackup -p PORT" --server-pre-command "bundle $LOCAL_BUNDLER_VERSION" --server-kill-match "rackup" -o ../data/rsb_rack_TIMESTAMP.json
    cd ..
  done

  unset BUNDLE_GEMFILE
  unset RSB_EXTRA_GEMFILES
done
