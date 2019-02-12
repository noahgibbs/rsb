#!/bin/bash -l

set -e
set -x

for CONC in 6 5 4 3 2 1
do
    export CONCURRENCY=$CONC
    ./runners/appserver_runs.sh
done
