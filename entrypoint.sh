#!/bin/bash
/xashds/watch_logs.sh &
exec ./xash +ip 0.0.0.0 -port 27015 -game cstrike "$@"
