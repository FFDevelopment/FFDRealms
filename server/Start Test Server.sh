#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")"
if [ ! -x .venv/bin/python ]; then
  python3 -m venv .venv
  .venv/bin/python -m pip install --upgrade pip
  .venv/bin/python -m pip install -r requirements.txt
fi
: "${FFDREALMS_ADMIN_KEY:=change-this-before-internet-use}"
export FFDREALMS_ADMIN_KEY
echo "Admin: http://127.0.0.1:8765/admin?key=$FFDREALMS_ADMIN_KEY"
exec .venv/bin/python server.py
