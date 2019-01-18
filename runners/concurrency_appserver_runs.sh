#!/bin/bash -l

set -e
set -x

for CONC in 1 2 3 4 5 6
do
    export CONCURRENCY=$CONC
    ./runners/appserver_runs.sh
done
