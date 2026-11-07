#!/QOpenSys/pkgs/bin/bash
# End-to-end demo of the integration objects, run on the IBM i (PASE).
#   bash integration/run_demo.sh            (from the repository root)
# Needs: programs built (makei build), sql/04_integration.sql run once,
# npm install in integration/node-api. The library list of the PASE job
# must contain the data library (DTALIB).
set -u
export PATH=/QOpenSys/pkgs/bin:$PATH
cd "$(dirname "$0")" || exit 1
OBJLIB=${OBJLIB:-DODIKIBMI1}
DTALIB=${DTALIB:-DODIKIBMI2}
OUT=$PWD/out
PORT=${PORT:-48401}
mkdir -p "$OUT"

# CALL from a command line passes a quoted string longer than 32 characters
# with its own length, not the 200 bytes the CL program declares: pad it.
pad() { printf "%-200s" "$1"; }

sql() {   # print the result of one SELECT as JSON lines
  python3.9 - "$1" <<'EOF'
import json, sys, ibm_db
c = ibm_db.connect("*LOCAL", None, None)
s = ibm_db.exec_immediate(c, sys.argv[1])
r = ibm_db.fetch_assoc(s)
while r:
    print(json.dumps({k: (str(v).rstrip() if v is not None else None) for k, v in r.items()}))
    r = ibm_db.fetch_assoc(s)
EOF
}

echo "=== 1. CSV export: stock status to $OUT/stock.csv"
system "CALL PGM($OBJLIB/INV820C) PARM('EXPORT' '$(pad "$OUT/stock.csv")')"
head -5 "$OUT/stock.csv"
echo "... $(wc -l < "$OUT/stock.csv") lines"

echo
echo "=== 2. CSV import: samples/price-update.csv (3 good rows, 2 rejected)"
system "CALL PGM($OBJLIB/INV820C) PARM('IMPORT' '$(pad "$PWD/samples/price-update.csv")')"
sql "SELECT PRITEM, PRPRICE, PRMINQ, PRRESULT FROM $DTALIB.PRICE_UPDATE_RESULT"
sql "SELECT ITITEM, ITPRICE, ITMINQ FROM $DTALIB.ITEM_MASTER WHERE ITITEM IN ('OF-0001','OF-0002','EL-0001') ORDER BY ITITEM"

echo
echo "=== 3. XML delivery note: good note, the same note again, a bad note"
sql "SELECT STITEM, STQTY FROM $DTALIB.STOCK_BALANCE WHERE STWHS = 'CTR' AND STITEM IN ('OF-0001','OF-0002','OF-0003','EL-0001') ORDER BY STITEM"
for f in delivery-note.xml delivery-note.xml delivery-note-bad.xml; do
  python3.9 - "$PWD/samples/$f" "$DTALIB" <<'EOF'
import sys, ibm_db
c = ibm_db.connect("*LOCAL", None, None)
r = ibm_db.callproc(c, sys.argv[2] + ".POST_DELIVERY_NOTE", (sys.argv[1].ljust(200), " " * 80))
print(sys.argv[1].rsplit("/", 1)[1], "->", r[2].strip())
EOF
done
sql "SELECT STITEM, STQTY FROM $DTALIB.STOCK_BALANCE WHERE STWHS = 'CTR' AND STITEM IN ('OF-0001','OF-0002','OF-0003','EL-0001') ORDER BY STITEM"

echo
echo "=== 4. Data queues: RPG server INV810R, clients in Python and Node.js"
python3.9 - "$DTALIB" <<'EOF'
import sys, ibm_db
c = ibm_db.connect("*LOCAL", None, None)
for q in ("INVREQQ", "INVRPYQ"):   # leftovers of an earlier run
    ibm_db.exec_immediate(c, f"CALL QSYS2.CLEAR_DATA_QUEUE('{q}', '{sys.argv[1]}')")
EOF
system "CALL PGM($OBJLIB/INV810R) PARM((60 (*DEC 5 0)))" > "$OUT/inv810r.log" 2>&1 &
RPG=$!
sleep 2
echo "--- Python client"
python3.9 dtaq_client.py OF-0001 ZZ-0000

echo "--- Node.js REST API on port $PORT"
(cd node-api && INV_SCHEMA=$DTALIB PORT=$PORT node server.js > "$OUT/node-api.log" 2>&1) &
NODE=$!
sleep 3
B=http://127.0.0.1:$PORT/api
show() { echo; echo ">>> $*"; curl -s -w '<<< HTTP %{http_code}\n' "$@"; }
show "$B/health"
show "$B/stock?warehouse=WST&reorder=Y"
show "$B/items/OF-0003/inquiry"
show -X POST "$B/movements" -H 'Content-Type: application/json' \
     -d '{"type":"O","item":"OF-0003","warehouse":"CTR","quantity":2,"reference":"NODE-DEMO"}'
show -X POST "$B/movements" -H 'Content-Type: application/json' \
     -d '{"type":"O","item":"OF-0003","warehouse":"CTR","quantity":99999,"reference":"NODE-DEMO"}'
show "$B/items/OF-0003/inquiry"

echo
echo "--- stop"
python3.9 dtaq_client.py --stop
wait $RPG
echo "INV810R ended (rc $?)"
kill $NODE 2>/dev/null
wait $NODE 2>/dev/null
echo "Node.js API stopped"
