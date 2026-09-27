#!/QOpenSys/pkgs/bin/bash
# Smoke test of the inventory REST API. Run in a second SSH session while
# server.py is running:   bash test_api.sh [base-url]
BASE=${1:-http://127.0.0.1:48400/api}

show() {
  echo
  echo "=== $1 $2"
  shift 2
  curl -s -w '\n--- HTTP %{http_code}\n' "$@"
}

show GET  "health"                 "$BASE/health"
show GET  "one item"               "$BASE/items/OF-0001"
show GET  "reorder list EST"       "$BASE/stock?warehouse=EST&reorder=Y"
show GET  "movements OF-0001 CTR"  "$BASE/movements?item=OF-0001&warehouse=CTR"

show POST "goods in (201)" -X POST "$BASE/movements" \
  -H 'Content-Type: application/json' \
  -d '{"type":"I","item":"OF-0001","warehouse":"CTR","quantity":10,"reference":"API-TEST-IN"}'

show POST "too much out (409)" -X POST "$BASE/movements" \
  -H 'Content-Type: application/json' \
  -d '{"type":"O","item":"EL-0005","warehouse":"CTR","quantity":999,"reference":"API-TEST-OUT"}'

show POST "unknown item (404)" -X POST "$BASE/movements" \
  -H 'Content-Type: application/json' \
  -d '{"type":"I","item":"XX-9999","warehouse":"CTR","quantity":1}'

show GET  "unknown route (404)"    "$BASE/nothing"
