#!/bin/bash
/xashds/watch_logs.sh &

#per defecte serà 27015
CURRENT_PORT=${PORT:-27015}

echo "Iniciant servidor Xash3D al port $CURRENT_PORT..."

exec ./xash +ip 0.0.0.0 -port "$CURRENT_PORT" -game cstrike "$@"
