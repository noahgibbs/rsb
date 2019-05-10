#!/bin/bash
# This is used by runner testers as the "wrk" binary to check what arguments are provided to it
echo "$@" >> /tmp/rsb_subprocess_args.txt
