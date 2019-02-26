#!/bin/bash -l

set -e
set -x

export RSB_RUBY_VERSION=${RSB_RUBY_VERSION:-`rvm current`}
export WRK_BENCH=${WRK_BENCH:-../wrk_bench.rb}
export WRK=${WRK:-~/wrk/wrk}

export BUNDLE_GEMFILE="Gemfile.$RSB_RUBY_VERSION"
export RAILS_ENV=${RSB_RACK_ENV:production}
export RACK_ENV=${RSB_RACK_ENV:production}

# Rails: migrate as precommand, use widget_tracker dir
cd widget_tracker
$WRK_BENCH --wrk-path $WRK --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 --server-command "bundle _1.17.3_ exec rails server -p PORT" --server-pre-command "bundle _1.17.3_ && bundle _1.17.3_ exec rake db:migrate" --server-kill-match "rails server" -o ../data/rsb_rails_TIMESTAMP.json
cd ..

# Rack: no precommand, use rack_hello_world dir
cd rack_hello_world
$WRK_BENCH --wrk-path $WRK --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 --server-command "bundle _1.17.3_ && bundle _1.17.3_ exec rackup -p PORT" --server-pre-command "bundle _1.17.3_" --server-kill-match "rackup" -o ../data/rsb_rack_TIMESTAMP.json
cd ..
