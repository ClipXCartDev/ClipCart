#!/usr/bin/env bash
# Keeps exactly one launch loop alive. A single transient failure should never
# end an overnight grind, so anything that isn't success gets restarted.
cd "$(dirname "$0")"
while true; do
  if python -c "
import sys; sys.path.insert(0, '.')
from oci_cli import run, TENANCY
sys.exit(0 if (run(['compute','instance','list','--compartment-id',TENANCY,'--all']) or []) else 1)
" 2>/dev/null; then
    echo "$(date '+%F %T') instance exists - supervisor done" >> supervisor.log
    exit 0
  fi
  echo "$(date '+%F %T') starting launch loop" >> supervisor.log
  python -u launch_instance.py >> launch.log 2>&1
  echo "$(date '+%F %T') loop exited (rc=$?) - restarting in 60s" >> supervisor.log
  sleep 60
done
