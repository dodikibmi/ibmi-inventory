"""Stock inquiry from Python through the data queues of INV810R.

Python 3.9 + ibm_db in PASE, local connection (no password, runs as the
user who starts it). Sends {"id":..., "item":...} to INVREQQ and waits for
the reply with the same key on INVRPYQ - the same contract the Node.js API
uses, so the RPG server does not know or care who is asking.

    python3.9 dtaq_client.py OF-0001 [OF-0002 ...]
    python3.9 dtaq_client.py --stop          ask INV810R to end
"""
import json
import os
import sys
import time

import ibm_db

SCHEMA = os.environ.get("INV_SCHEMA", "DODIKIBMI2").upper()
WAIT = int(os.environ.get("INQUIRY_WAIT", "5"))


def send(conn, message):
    sql = ("CALL QSYS2.SEND_DATA_QUEUE_UTF8(MESSAGE_DATA => ?,"
           " DATA_QUEUE => 'INVREQQ', DATA_QUEUE_LIBRARY => ?)")
    ibm_db.execute(ibm_db.prepare(conn, sql), (json.dumps(message), SCHEMA))


def ask(conn, item, n):
    req_id = f"P{int(time.time()) % 100000:05d}-{n}"   # A-Z 0-9 - only
    send(conn, {"id": req_id, "item": item.upper()})
    stmt = ibm_db.prepare(conn,
        "SELECT MESSAGE_DATA_UTF8 FROM TABLE(QSYS2.RECEIVE_DATA_QUEUE("
        "DATA_QUEUE => 'INVRPYQ', DATA_QUEUE_LIBRARY => ?, WAIT_TIME => ?,"
        " KEY_DATA => ?, KEY_ORDER => 'EQ'))")
    ibm_db.execute(stmt, (SCHEMA, WAIT, req_id.ljust(16)))
    row = ibm_db.fetch_tuple(stmt)
    if not row:
        return {"id": req_id, "error": f"no answer within {WAIT} s"}
    return json.loads(row[0])


def main(args):
    conn = ibm_db.connect("*LOCAL", None, None)   # None, not ""
    try:
        if args == ["--stop"]:
            send(conn, {"cmd": "stop"})
            print("stop sent")
            return 0
        for n, item in enumerate(args, 1):
            print(json.dumps(ask(conn, item, n), indent=2))
        return 0
    finally:
        ibm_db.close(conn)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]) if len(sys.argv) > 1 else print(__doc__))
