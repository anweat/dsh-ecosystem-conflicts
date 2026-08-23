#!/usr/bin/env bash
# Wait for the harvester to land data/repos.json, then run the batch:
# clone -> extract -> report. Safe to re-run; clones are cached.
set -euo pipefail
cd "$(dirname "$0")"

LIMIT="${1:-2000}"
CONCURRENCY="${2:-16}"

echo "[pipeline] waiting for data/repos.json ..."
for _ in $(seq 1 600); do
  [ -f data/repos.json ] && break
  sleep 5
done
if [ ! -f data/repos.json ]; then
  echo "[pipeline] harvest never produced data/repos.json" >&2
  exit 1
fi
echo "[pipeline] repos.json ready: $(node -e "console.log(JSON.parse(require('fs').readFileSync('data/repos.json','utf8')).length)") repos"

echo "[pipeline] cloning (limit=$LIMIT concurrency=$CONCURRENCY) ..."
node 02-clone.mjs --limit "$LIMIT" --concurrency "$CONCURRENCY"

echo "[pipeline] extracting ..."
node 03-extract.mjs

echo "[pipeline] reporting ..."
node 04-report.mjs

echo "[pipeline] done"
