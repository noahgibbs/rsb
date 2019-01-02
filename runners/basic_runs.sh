#!/bin/bash -l

# 2.5.3
# 2.4.5
# 2.3.8
# 2.2.10
# 2.1.10
# 2.0.0-p648
# 2.0.0-p0 (Can't be installed on current Mac with current compiler)

for RSB_RUBY_VERSION in ["2.0.0-p0", "2.0.0-p648", "2.1.10", "2.2.10", "2.3.8", "2.4.5", "2.5.3", "2.6.0"]; do
  rvm use $RSB_RUBY_VERSION

  export BUNDLE_GEMFILE="Gemfile.$RSB_RUBY_VERSION"
  export RAILS_ENV=production
  export RACK_ENV=production

  # Rails: migrate as precommand, use widget_tracker dir
  cd widget_tracker
  ../ab_bench.rb --url http://127.0.0.1:PORT/simple_bench/static -n 10000 -w 100 --server-command "rails server -p PORT" --server-pre-command "bundle exec rake db:migrate" -o rsb_rails_TIMESTAMP.json
  cd ..

  # Rack: no precommand, use rack_hello_world dir
  cd rack_hello_world
  ../ab_bench.rb --url http://127.0.0.1:PORT/simple_bench/static -n 10000 -w 100 --server-command "rackup -p PORT" --server-pre-command "echo Skip..." -o rsb_rack_TIMESTAMP.json
  cd ..
done
