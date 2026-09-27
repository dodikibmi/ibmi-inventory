"""IBM i Warehouse Inventory - REST API.

Runs in PASE on the IBM i itself with Python 3.9 and the ibm_db driver
(both ship with the IBM i open-source packages). Standard library only:
no framework has to be installed.

Endpoints
  GET  /api/health
  GET  /api/items?category=OFFC&status=A
  GET  /api/items/{code}                 item with stock per warehouse
  GET  /api/stock?warehouse=CTR&reorder=Y
  GET  /api/movements?item=OF-0001&warehouse=CTR&from=2026-09-01
  POST /api/movements                    body: {"type":"I","item":"OF-0001",
                                         "warehouse":"CTR","quantity":10,
                                         "date":"2026-09-26","reference":"PO-1"}

POST calls the SQL procedure POST_MOVEMENT (sql/03_api.sql), which holds the
same posting rules as the green-screen program INV200R. The API commits on
success and rolls back on any error, so stock and movement history never
drift apart.

Start (in an SSH session on the IBM i):
  INV_DB=PUB400 INV_SCHEMA=DODIKIBMI2 PORT=48400 python3.9 server.py
INV_DB is the local relational database name of the system. Where a local
connection needs a user, also export INV_USER and INV_PASSWORD (read the
password with `read -s` so it never appears on screen or in the history).
"""
import datetime
import decimal
import faulthandler
import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

import ibm_db

SCHEMA = os.environ.get("INV_SCHEMA", "DODIKIBMI2").upper()
# Local relational database name (WRKRDBDIRE entry *LOCAL, or
# SELECT CURRENT SERVER FROM SYSIBM.SYSDUMMY1). With an empty user the
# PASE driver connects locally as the user who started the server.
DATABASE = os.environ.get("INV_DB", "*LOCAL").upper()
# Some systems (PUB400 among them) refuse a local connection without a user
# (SQL30082). Then set INV_USER and INV_PASSWORD in the shell; the password
# is read from the environment only, never stored in code or files.
DB_USER = os.environ.get("INV_USER", "")
DB_PASSWORD = os.environ.get("INV_PASSWORD", "")
PORT = int(os.environ.get("PORT", "48400"))
HOST = os.environ.get("HOST", "127.0.0.1")

# SQLSTATE raised by POST_MOVEMENT -> HTTP status
BUSINESS_ERRORS = {
    "75001": 400, "75002": 404, "75003": 404,
    "75004": 400, "75005": 400, "75006": 409,
}

_conn = None


def connection():
    """The one database connection of the server.

    Local database of this IBM i, as the user who started the server. The
    PASE CLI driver (without server mode) supports one local connection per
    job, so the server opens it once and handles requests one at a time.
    """
    global _conn
    if _conn is None or not ibm_db.active(_conn):
        _conn = ibm_db.connect(DATABASE, DB_USER, DB_PASSWORD)
        ibm_db.autocommit(_conn, ibm_db.SQL_AUTOCOMMIT_OFF)
        ibm_db.exec_immediate(_conn, f"SET SCHEMA {SCHEMA}")
    return _conn


def db_error(exc):
    """Driver message of the last failed call, or the exception text."""
    detail = ibm_db.stmt_errormsg() or ibm_db.conn_errormsg() or ""
    return f"{exc} {detail}".strip()


def rows(sql, params=()):
    """Run a SELECT and return a list of dicts with trimmed strings."""
    stmt = ibm_db.prepare(connection(), sql)
    try:
        ibm_db.execute(stmt, tuple(params))
        numeric = {ibm_db.field_name(stmt, i).lower()
                   for i in range(ibm_db.num_fields(stmt))
                   if ibm_db.field_type(stmt, i) in ("decimal", "numeric")}
        out = []
        row = ibm_db.fetch_assoc(stmt)
        while row:
            rec = {}
            for key, value in row.items():
                key = key.lower()
                if key in numeric and value is not None:
                    value = decimal.Decimal(str(value))
                elif isinstance(value, str):
                    value = value.rstrip()
                rec[key] = value
            out.append(rec)
            row = ibm_db.fetch_assoc(stmt)
    finally:
        # release the statement: with a server-mode connection an open
        # handle can keep the next statement waiting
        ibm_db.free_stmt(stmt)
    ibm_db.commit(connection())
    return out


def to_json(obj):
    def default(value):
        if isinstance(value, decimal.Decimal):
            return int(value) if value == value.to_integral() else float(value)
        if isinstance(value, (datetime.date, datetime.datetime)):
            return value.isoformat()
        raise TypeError(type(value).__name__)
    return json.dumps(obj, default=default, indent=2).encode("utf-8")


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


# ------------------------------------------------------------------ handlers
def get_health(_q):
    return {"status": "ok", "schema": SCHEMA,
            "database": rows("SELECT CURRENT SERVER AS name"
                             " FROM SYSIBM.SYSDUMMY1")[0]["name"]}


def get_items(q):
    sql = ("SELECT ITITEM AS item, ITDESC AS description, ITCATG AS category,"
           " ITUOM AS uom, ITPRICE AS price, ITMINQ AS minimum, ITSTAT AS status"
           " FROM ITEM_MASTER WHERE 1 = 1")
    params = []
    if "category" in q:
        sql += " AND ITCATG = ?"
        params.append(q["category"].upper())
    if "status" in q:
        sql += " AND ITSTAT = ?"
        params.append(q["status"].upper())
    return {"items": rows(sql + " ORDER BY ITITEM", params)}


def get_item(_q, code):
    found = rows("SELECT ITITEM AS item, ITDESC AS description,"
                 " ITCATG AS category, ITUOM AS uom, ITPRICE AS price,"
                 " ITMINQ AS minimum, ITSTAT AS status,"
                 " ITCHGU AS changed_by, ITCHGT AS changed_at"
                 " FROM ITEM_MASTER WHERE ITITEM = ?", [code.upper()])
    if not found:
        raise ApiError(404, f"Item {code} not found")
    item = found[0]
    item["stock"] = rows("SELECT STWHS AS warehouse, WHNAME AS name,"
                         " STQTY AS on_hand, REORDER AS reorder"
                         " FROM STOCK_STATUS WHERE STITEM = ?"
                         " ORDER BY STWHS", [code.upper()])
    item["on_hand_total"] = sum(s["on_hand"] for s in item["stock"])
    return item


def get_stock(q):
    sql = ("SELECT STWHS AS warehouse, STITEM AS item, ITDESC AS description,"
           " STQTY AS on_hand, ITMINQ AS minimum, STVALUE AS value,"
           " REORDER AS reorder FROM STOCK_STATUS WHERE 1 = 1")
    params = []
    if "warehouse" in q:
        sql += " AND STWHS = ?"
        params.append(q["warehouse"].upper())
    if q.get("reorder", "").upper() == "Y":
        sql += " AND REORDER = 'Y'"
    data = rows(sql + " ORDER BY STWHS, STITEM", params)
    return {"count": len(data), "stock": data}


def get_movements(q):
    if "item" not in q:
        raise ApiError(400, "Query parameter 'item' is required")
    sql = ("SELECT MVNO AS number, MVDATE AS date, MVTYPE AS type,"
           " MVWHS AS warehouse, MVQTY AS quantity, MVREF AS reference,"
           " MVUSER AS entered_by FROM STOCK_MOVEMENT WHERE MVITEM = ?")
    params = [q["item"].upper()]
    if "warehouse" in q:
        sql += " AND MVWHS = ?"
        params.append(q["warehouse"].upper())
    if "from" in q:
        sql += " AND MVDATE >= ?"
        params.append(q["from"])
    return {"movements": rows(sql + " ORDER BY MVDATE, MVNO", params)}


def post_movement(body):
    try:
        mtype = str(body["type"]).upper()
        item = str(body["item"]).upper()
        whs = str(body["warehouse"]).upper()
        qty = int(body["quantity"])
        date = body.get("date") or datetime.date.today().isoformat()
        datetime.date.fromisoformat(date)
        ref = str(body.get("reference", ""))[:20]
    except (KeyError, TypeError, ValueError) as exc:
        raise ApiError(400, f"Invalid body: {exc}") from exc

    conn = connection()
    stmt = None
    try:
        # OUT parameters get a buffer as wide as their initial value and
        # the driver does not clear what follows the returned digits, so
        # they start as 9 blanks (DECIMAL(9, 0)); out_number() drops them
        result = ibm_db.callproc(conn, f"{SCHEMA}.POST_MOVEMENT",
                                 (mtype, item, whs, qty, date, ref,
                                  " " * 9, " " * 9))
        # (statement, param1 ... param8): OUT params are 7 and 8
        stmt = result[0]
        number, on_hand = result[7], result[8]
        ibm_db.commit(conn)
    except Exception as exc:  # noqa: BLE001 - map every database error
        # read the error before the rollback clears it
        state = ibm_db.stmt_error() or ""
        message = ibm_db.stmt_errormsg() or str(exc)
        try:
            ibm_db.rollback(conn)
        except Exception:  # noqa: BLE001
            pass
        status = BUSINESS_ERRORS.get(state[:5], 500)
        # "Message <text> returned from SIGNAL ..." -> <text>
        found = re.search(r"Message (.+?) returned from SIGNAL", message)
        text = found.group(1) if status != 500 and found else message
        raise ApiError(status, text) from exc
    finally:
        if stmt:
            ibm_db.free_stmt(stmt)
    return {"number": out_number(number), "item": item,
            "warehouse": whs, "type": mtype, "quantity": qty, "date": date,
            "on_hand": out_number(on_hand)}


def out_number(value):
    """OUT parameter as int; the driver may pad it with blanks or NULs."""
    digits = re.sub(r"[^0-9-]", "", str(value))
    return int(digits) if digits else None


ROUTES = [
    ("GET", re.compile(r"^/api/health$"), get_health),
    ("GET", re.compile(r"^/api/items$"), get_items),
    ("GET", re.compile(r"^/api/items/([^/]+)$"), get_item),
    ("GET", re.compile(r"^/api/stock$"), get_stock),
    ("GET", re.compile(r"^/api/movements$"), get_movements),
]


class Handler(BaseHTTPRequestHandler):
    server_version = "IBMiInventoryAPI/1.0"

    def handle_one_request(self):
        # watchdog: a request still running after 20 s prints the Python
        # stack to the log, so a hang shows the exact line it waits on
        faulthandler.dump_traceback_later(20, exit=False)
        try:
            super().handle_one_request()
        finally:
            faulthandler.cancel_dump_traceback_later()

    def _send(self, status, payload):
        body = to_json(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802 - http.server naming
        url = urlparse(self.path)
        query = {k: v[0] for k, v in parse_qs(url.query).items()}
        try:
            for method, pattern, handler in ROUTES:
                match = pattern.match(url.path)
                if method == "GET" and match:
                    self._send(200, handler(query, *match.groups()))
                    return
            raise ApiError(404, f"No route for {url.path}")
        except ApiError as err:
            self._send(err.status, {"error": err.message})
        except Exception as exc:  # noqa: BLE001
            self._send(500, {"error": db_error(exc)})

    def do_POST(self):  # noqa: N802
        if urlparse(self.path).path != "/api/movements":
            self._send(404, {"error": f"No route for POST {self.path}"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length) or b"{}")
            self._send(201, post_movement(body))
        except json.JSONDecodeError:
            self._send(400, {"error": "Body is not valid JSON"})
        except ApiError as err:
            self._send(err.status, {"error": err.message})
        except Exception as exc:  # noqa: BLE001 - never drop the connection
            self._send(500, {"error": f"{type(exc).__name__}: {db_error(exc)}"})

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.log_date_time_string(), fmt % args))


def main():
    try:
        connection()
    except Exception as exc:  # noqa: BLE001
        sys.exit(f"Cannot connect to Db2: {db_error(exc)}")
    server = HTTPServer((HOST, PORT), Handler)
    print(f"Inventory API on http://{HOST}:{PORT}/api  (schema {SCHEMA})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
