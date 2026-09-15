#!/bin/bash
# Stub hermes CLI: `kanban list` returns one fake running task; other calls recorded.
CALLS="$FAKHOME/calls.txt"
case "$1 $2" in
  "kanban list") python3 -c "import json,sys,time;print(json.dumps([{'id':'t_test1234','workspace_path':'/tmp/stall-sandbox/empty_ws','started_at':int(time.time())-3600}]))" ;;
  *) echo "$1 $2 $3 $4 $5" >> "$CALLS" ;;
esac
