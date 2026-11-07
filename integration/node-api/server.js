'use strict';
/*
 * IBM i Warehouse Inventory - REST API provider in Node.js (PASE).
 *
 * Runs on the IBM i itself. Node.js core http module + idb-connector (the
 * IBM Db2 for i driver for Node.js, a local *LOCAL connection: no password,
 * the job runs under the user who starts it).
 *
 *   GET  /                                   stock dashboard (../web, static)
 *   GET  /api/health
 *   GET  /api/stock?warehouse=CTR&reorder=Y      stock status view
 *   GET  /api/items/{code}/inquiry               answered by the RPG server
 *                                                INV810R over data queues
 *   POST /api/movements                          SQL procedure POST_MOVEMENT
 *        {"type":"I","item":"OF-0001","warehouse":"CTR","quantity":10,
 *         "date":"2026-11-07","reference":"PO-1"}
 *
 * Same contract and the same posting rules as the Python API (api/server.py):
 * business errors from POST_MOVEMENT (SQLSTATE 75001-75006) become HTTP 4xx.
 *
 * Start:  INV_SCHEMA=DODIKIBMI2 PORT=48401 node server.js
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');
const db = require('idb-connector');

const SCHEMA = (process.env.INV_SCHEMA || 'DODIKIBMI2').toUpperCase();
const PORT = Number(process.env.PORT || 48401);
const INQUIRY_WAIT = Number(process.env.INQUIRY_WAIT || 5); // seconds

if (!/^[A-Z0-9_#$@]{1,10}$/.test(SCHEMA)) throw new Error('bad INV_SCHEMA');

// the dashboard: a fixed list of files, so no path from the URL reaches the disk
const WEB = path.join(__dirname, '..', 'web');
const STATIC = {
  '/': ['index.html', 'text/html; charset=utf-8'],
  '/index.html': ['index.html', 'text/html; charset=utf-8'],
  '/app.js': ['app.js', 'text/javascript; charset=utf-8'],
  '/style.css': ['style.css', 'text/css; charset=utf-8'],
};

// ---- database helpers (one connection per request: simple and safe) -------
function connect(autocommit = true) {
  const conn = new db.dbconn();
  conn.setConnAttr(db.SQL_ATTR_DBC_SYS_NAMING, db.SQL_FALSE);
  conn.setConnAttr(db.SQL_ATTR_DBC_DEFAULT_LIB, SCHEMA);
  if (!autocommit) {
    conn.setConnAttr(db.SQL_ATTR_COMMIT, db.SQL_COMMIT_CHG);
    conn.setConnAttr(db.SQL_ATTR_AUTOCOMMIT, db.SQL_FALSE);
  }
  conn.conn('*LOCAL');
  return conn;
}

function close(conn) {
  try { conn.disconn(); conn.close(); } catch (e) { /* already closed */ }
}

// prepare + bind + execute + fetchAll as one promise
function query(conn, sql, params = []) {
  return new Promise((resolve, reject) => {
    const st = new db.dbstmt(conn);
    const done = (err, val) => { st.close(); err ? reject(err) : resolve(val); };
    st.prepare(sql, (e1) => {
      if (e1) return done(e1);
      st.bindParameters(params, (e2) => {
        if (e2) return done(e2);
        st.execute((out, e3) => {
          if (e3) return done(e3);
          if (/^\s*CALL\b/i.test(sql)) return done(null, out || []); // no result set
          st.fetchAll((rows, e4) => done(e4, rows || []));
        });
      });
    });
  });
}

// ---- small HTTP helpers ---------------------------------------------------
function send(res, status, body) {
  const text = JSON.stringify(body, null, 2);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(text + '\n');
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (c) => {
      data += c;
      if (data.length > 10000) reject(new Error('body too large'));
    });
    req.on('end', () => {
      try { resolve(JSON.parse(data || '{}')); } catch (e) { reject(e); }
    });
  });
}

const BUSINESS = { // SQLSTATEs signalled by POST_MOVEMENT
  75001: 400, 75002: 400, 75003: 404, 75004: 404, 75005: 400, 75006: 409,
};

function sqlState(err) {
  const m = /SQLSTATE=(\w{5})/.exec(String(err && err.message));
  return m ? m[1] : '';
}

function errText(err) {
  const text = String(err && err.message).replace(/^SQLSTATE=\w+ SQLCODE=-?\d+\s*/, '');
  const m = /Message (.*) returned from SIGNAL/.exec(text); // SQL0438 text
  return m ? m[1] : text;
}

// ---- handlers -----------------------------------------------------------
async function stock(url) {
  const where = [];
  const params = [];
  const whs = url.searchParams.get('warehouse');
  if (whs) { where.push('STWHS = ?'); params.push(whs.toUpperCase()); }
  if (url.searchParams.get('reorder') === 'Y') where.push("REORDER = 'Y'");
  const sql = 'SELECT TRIM(STWHS) AS "warehouse", TRIM(WHNAME) AS "warehouseName",'
    + ' TRIM(STITEM) AS "item", TRIM(ITDESC) AS "description", STQTY AS "quantity",'
    + ' ITMINQ AS "minimum", ITPRICE AS "price", STVALUE AS "value", REORDER AS "reorder"'
    + ' FROM STOCK_STATUS'
    + (where.length ? ' WHERE ' + where.join(' AND ') : '')
    + ' ORDER BY STWHS, STITEM';
  const conn = connect();
  try {
    const rows = await query(conn, sql, params);
    rows.forEach((r) => {
      for (const k of ['quantity', 'minimum', 'price', 'value']) r[k] = Number(r[k]);
    });
    return [200, { count: rows.length, stock: rows }];
  } finally { close(conn); }
}

// Node asks, RPG answers: request on INVREQQ, reply on keyed INVRPYQ
let seq = 0;
async function inquiry(item) {
  const id = ('N' + Date.now().toString(36) + '-' + (++seq)).toUpperCase().slice(0, 16);
  const msg = JSON.stringify({ id, item: item.toUpperCase() });
  const conn = connect();
  try {
    await query(conn,
      'CALL QSYS2.SEND_DATA_QUEUE_UTF8(MESSAGE_DATA => ?,'
      + " DATA_QUEUE => 'INVREQQ', DATA_QUEUE_LIBRARY => ?)", [msg, SCHEMA]);
    const rows = await query(conn,
      'SELECT MESSAGE_DATA_UTF8 AS "reply"'
      + ' FROM TABLE(QSYS2.RECEIVE_DATA_QUEUE(DATA_QUEUE => \'INVRPYQ\','
      + ' DATA_QUEUE_LIBRARY => ?, WAIT_TIME => ?, KEY_DATA => ?,'
      + " KEY_ORDER => 'EQ'))",
      [SCHEMA, INQUIRY_WAIT, id.padEnd(16)]);
    if (!rows.length) {
      return [504, { error: 'no answer from INV810R within '
        + INQUIRY_WAIT + ' s - is the server job running?', id }];
    }
    const reply = JSON.parse(rows[0].reply);
    return [reply.error ? 404 : 200, reply];
  } finally { close(conn); }
}

async function postMovement(req) {
  const b = await readJson(req);
  for (const f of ['type', 'item', 'warehouse', 'quantity']) {
    if (b[f] === undefined || b[f] === '') return [400, { error: f + ' is required' }];
  }
  const conn = connect(false); // one unit of work: commit or roll back
  const st = new db.dbstmt(conn);
  const step = (fn) => new Promise((resolve, reject) => fn((x, e) => (e ? reject(e) : resolve(x))));
  try {
    await step((cb) => st.prepare('CALL POST_MOVEMENT(?, ?, ?, ?, ?, ?, ?, ?)', (e) => cb(null, e)));
    await step((cb) => st.bindParam([
      [String(b.type).toUpperCase(), db.IN, db.CHAR],
      [String(b.item).toUpperCase(), db.IN, db.CHAR],
      [String(b.warehouse).toUpperCase(), db.IN, db.CHAR],
      [Number(b.quantity), db.IN, db.NUMERIC],
      [b.date || new Date().toISOString().slice(0, 10), db.IN, db.CHAR],
      [String(b.reference || 'NODE-API').slice(0, 20), db.IN, db.CHAR],
      [0, db.OUT, db.NUMERIC],
      [0, db.OUT, db.NUMERIC],
    ], (e) => cb(null, e)));
    const out = await step((cb) => st.execute((o, e) => cb(o, e)));
    // idb-connector 1.3: commit()/rollback() run synchronously and never
    // call a callback - awaiting one hangs the request
    st.commit();
    return [201, { movement: Number(out[0]), newQuantity: Number(out[1]) }];
  } catch (err) {
    try { st.rollback(); } catch (e) { /* nothing to undo */ }
    const status = BUSINESS[sqlState(err)];
    if (status) return [status, { error: errText(err), sqlstate: sqlState(err) }];
    throw err;
  } finally { st.close(); close(conn); }
}

// ---- router -------------------------------------------------------------
async function route(req) {
  const url = new URL(req.url, 'http://localhost');
  const p = url.pathname.replace(/\/+$/, '');
  if (req.method === 'GET' && p === '/api/health') {
    const conn = connect();
    try {
      const r = await query(conn, 'SELECT CURRENT SERVER AS "db", CURRENT USER AS "user"'
        + ' FROM SYSIBM.SYSDUMMY1');
      return [200, { status: 'ok', runtime: 'node ' + process.version, ...r[0], schema: SCHEMA }];
    } finally { close(conn); }
  }
  if (req.method === 'GET' && p === '/api/stock') return stock(url);
  const m = /^\/api\/items\/([A-Za-z0-9-]{1,10})\/inquiry$/.exec(p);
  if (req.method === 'GET' && m) return inquiry(m[1]);
  if (req.method === 'POST' && p === '/api/movements') return postMovement(req);
  return [404, { error: 'no such endpoint: ' + req.method + ' ' + p }];
}

http.createServer((req, res) => {
  const file = req.method === 'GET' && STATIC[req.url.split('?')[0]];
  if (file) {
    fs.readFile(path.join(WEB, file[0]), (err, data) => {
      res.writeHead(err ? 404 : 200, { 'Content-Type': file[1], 'Cache-Control': 'no-cache' });
      res.end(err ? 'not found' : data);
    });
    return;
  }
  route(req)
    .then(([status, body]) => send(res, status, body))
    .catch((err) => {
      console.error(new Date().toISOString(), req.method, req.url, err.message);
      send(res, 500, { error: 'internal error', detail: errText(err) });
    });
}).listen(PORT, '127.0.0.1', () => {
  console.log(`inventory Node.js API on http://127.0.0.1:${PORT}/api (schema ${SCHEMA})`);
});
