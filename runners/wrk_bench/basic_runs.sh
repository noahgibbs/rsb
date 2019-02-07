#!/bin/bash -l

set -e
set -x

for RSB_RUBY_VERSION in 2.0.0-p0 2.0.0-p648 2.1.10 2.2.10 2.3.8 2.4.5 2.5.3 2.6.0
do
  rvm use $RSB_RUBY_VERSION

  export BUNDLE_GEMFILE="Gemfile.$RSB_RUBY_VERSION"
  export RAILS_ENV=production
  export RACK_ENV=production

  # Rails: migrate as precommand, use widget_tracker dir
  cd widget_tracker
  ../wrk_bench.rb --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 --server-command "bundle _1.17.3_ exec rails server -p PORT" --server-pre-command "bundle _1.17.3_ && bundle _1.17.3_ exec rake db:migrate" --server-kill-match "rails server" -o ../data/rsb_rails_TIMESTAMP.json
  cd ..

  # Rack: no precommand, use rack_hello_world dir
  cd rack_hello_world
  ../wrk_bench.rb --url http://127.0.0.1:PORT/simple_bench/static -n 180 -w 20 --server-command "bundle _1.17.3_ && bundle _1.17.3_ exec rackup -p PORT" --server-pre-command "bundle _1.17.3_" --server-kill-match "rackup" -o ../data/rsb_rack_TIMESTAMP.json
  cd ..
done
