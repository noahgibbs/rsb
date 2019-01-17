#!/bin/bash -l

set -e
set -x

for CONCURRENCY in 1 2 3 4 5 6
do
    ./runners/appserver_runs.sh
done
