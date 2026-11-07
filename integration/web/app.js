'use strict';
// Stock dashboard: plain browser JavaScript, no framework, no build step.
// Every number comes from the Node.js API on the IBM i (integration/node-api).

const API = 'api';
const $ = (id) => document.getElementById(id);
let stock = [];           // all rows from GET /api/stock
let whsNames = {};

const nf = new Intl.NumberFormat('en-US');
function compact(n) {     // 1,284 / 12.9K / 4.2M / 1.3B
  const a = Math.abs(n);
  if (a >= 1e9) return (n / 1e9).toFixed(1) + 'B';
  if (a >= 1e6) return (n / 1e6).toFixed(1) + 'M';
  if (a >= 1e4) return (n / 1e3).toFixed(1) + 'K';
  return nf.format(n);
}
const rp = (n) => 'Rp ' + compact(n);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

async function call(path, options) {
  const t0 = performance.now();
  const res = await fetch(API + path, options);
  const body = await res.json().catch(() => ({}));
  return { status: res.status, body, ms: Math.round(performance.now() - t0) };
}

// ---- health -------------------------------------------------------------
async function health() {
  try {
    const r = await call('/health');
    $('health').innerHTML = r.status === 200
      ? `<span class="dot" style="background:var(--good)"></span>Connected &middot; ${esc(r.body.db)} &middot; ${esc(r.body.schema)} &middot; ${esc(r.body.runtime)}`
      : `<span class="dot" style="background:var(--critical)"></span>API error ${r.status}`;
  } catch (e) {
    $('health').innerHTML = '<span class="dot" style="background:var(--critical)"></span>API not reachable';
  }
}

// ---- data + filters -----------------------------------------------------
async function load() {
  const r = await call('/stock');
  stock = r.body.stock || [];
  whsNames = {};
  stock.forEach((s) => { whsNames[s.warehouse] = s.warehouseName || s.warehouse; });
  const sel = $('fWhs');
  const keep = sel.value;
  sel.innerHTML = '<option value="">All warehouses</option>'
    + Object.keys(whsNames).sort().map((w) => `<option value="${esc(w)}">${esc(w)} &ndash; ${esc(whsNames[w])}</option>`).join('');
  sel.value = keep;
  render();
}

function filtered() {
  const w = $('fWhs').value;
  const only = $('fReorder').checked;
  const t = $('fText').value.trim().toUpperCase();
  return stock.filter((s) => (!w || s.warehouse === w)
    && (!only || s.reorder === 'Y')
    && (!t || s.item.includes(t) || s.description.toUpperCase().includes(t)));
}

function render() {
  const rows = filtered();
  const value = rows.reduce((a, s) => a + s.value, 0);
  const units = rows.reduce((a, s) => a + s.quantity, 0);
  const reorder = rows.filter((s) => s.reorder === 'Y');
  $('kValue').textContent = rp(value);
  $('kValueNote').textContent = 'Rp ' + nf.format(Math.round(value));
  $('kReorder').textContent = nf.format(reorder.length);
  $('kLines').textContent = nf.format(rows.length);
  $('kUnits').textContent = compact(units);
  $('kUnitsNote').textContent = 'in ' + new Set(rows.map((s) => s.warehouse)).size + ' warehouse(s)';
  $('count').textContent = '(' + rows.length + ' lines)';
  $('rows').innerHTML = rows.map((s) => `
    <tr tabindex="0" data-item="${esc(s.item)}" data-whs="${esc(s.warehouse)}">
      <td>${esc(s.warehouse)}</td><td>${esc(s.item)}</td><td>${esc(s.description)}</td>
      <td class="num">${nf.format(s.quantity)}</td><td class="num">${nf.format(s.minimum)}</td>
      <td class="num">${nf.format(Math.round(s.value))}</td>
      <td>${s.reorder === 'Y'
        ? '<span class="status reorder"><i aria-hidden="true"></i>Reorder</span>'
        : '<span class="status okay"><i aria-hidden="true"></i>OK</span>'}</td>
    </tr>`).join('') || '<tr><td colspan="7" class="muted">No stock lines match the filters.</td></tr>';
  chart(rows);
}

// ---- bar chart: one series, one hue, value at the bar end, hover tooltip ---
function chart(rows) {
  const by = {};
  rows.forEach((s) => { by[s.warehouse] = (by[s.warehouse] || 0) + s.value; });
  const data = Object.entries(by).sort((a, b) => b[1] - a[1]);
  if (!data.length) { $('chart').innerHTML = '<p class="muted">No data for these filters.</p>'; return; }
  const W = 560; const rowH = 34; const barH = 16; const left = 200; const right = 70;
  const H = data.length * rowH + 28;
  const max = Math.max(...data.map((d) => d[1]));
  const x = (v) => (v / max) * (W - left - right);
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f) => f * max);
  let svg = `<svg viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg">`;
  ticks.forEach((t) => {
    const gx = left + x(t);
    svg += `<line class="gridline" x1="${gx}" x2="${gx}" y1="4" y2="${H - 22}"/>`
      + `<text class="lbl" x="${gx}" y="${H - 6}" text-anchor="middle">${t ? compact(t) : '0'}</text>`;
  });
  data.forEach(([w, v], i) => {
    const y = 8 + i * rowH;
    const bw = Math.max(x(v), 2);
    // 4px rounded data end, square at the baseline
    const r = Math.min(4, bw);
    const path = `M${left},${y} h${bw - r} a${r},${r} 0 0 1 ${r},${r} v${barH - 2 * r} a${r},${r} 0 0 1 -${r},${r} h-${bw - r} z`;
    svg += `<g data-tip="<div>${esc(w)} &ndash; ${esc(whsNames[w])}</div><b>Rp ${nf.format(Math.round(v))}</b>">`
      + `<rect class="hit" x="0" y="${y - 8}" width="${W}" height="${rowH}"/>`
      + `<path class="bar" d="${path}"/>`
      + `<text class="lbl" x="${left - 10}" y="${y + barH - 4}" text-anchor="end">${esc(w)} · ${esc(whsNames[w])}</text>`
      + `<text class="val" x="${left + bw + 6}" y="${y + barH - 4}">${compact(v)}</text></g>`;
  });
  svg += `<line class="baseline" x1="${left}" x2="${left}" y1="4" y2="${H - 22}"/></svg>`;
  $('chart').innerHTML = svg;
  $('chart').querySelectorAll('g[data-tip]').forEach((g) => {
    g.addEventListener('mousemove', (e) => tip(e, g.dataset.tip));
    g.addEventListener('mouseleave', () => { $('tip').hidden = true; });
  });
}

function tip(e, html) {
  const t = $('tip');
  t.innerHTML = html;
  t.hidden = false;
  t.style.left = Math.min(e.clientX + 12, window.innerWidth - t.offsetWidth - 8) + 'px';
  t.style.top = (e.clientY + 12) + 'px';
}

// ---- inquiry: browser -> Node.js -> data queue -> RPG -------------------
async function inquiry(item) {
  $('inqItem').value = item;
  $('inqOut').className = 'out muted';
  $('inqOut').textContent = 'Asking INV810R about ' + item + '…';
  const r = await call('/items/' + encodeURIComponent(item) + '/inquiry');
  const b = r.body;
  if (r.status !== 200) {
    $('inqOut').className = 'out err';
    $('inqOut').textContent = `${r.status}: ${b.error || 'no answer'}`;
    return;
  }
  $('inqOut').className = 'out';
  $('inqOut').innerHTML = `<b>${esc(b.item)}</b> ${esc(b.description)} &middot; unit ${esc(b.unit)} &middot; minimum ${nf.format(b.minimum)}
    <table><thead><tr><th>Warehouse</th><th class="num">Quantity</th><th>Status</th></tr></thead><tbody>
    ${(b.stock || []).map((s) => `<tr><td>${esc(s.warehouse)}</td><td class="num">${nf.format(s.quantity)}</td>
      <td>${s.reorder === 'Y' ? '<span class="status reorder"><i aria-hidden="true"></i>Reorder</span>' : '<span class="status okay"><i aria-hidden="true"></i>OK</span>'}</td></tr>`).join('')}
    </tbody></table>
    <div class="meta">Answered by RPG program INV810R via data queues in ${r.ms} ms &middot; request id ${esc(b.id)}</div>`;
}

// ---- post a movement ------------------------------------------------------
async function post(e) {
  e.preventDefault();
  const body = {
    type: $('mvType').value, item: $('mvItem').value.trim(), warehouse: $('mvWhs').value.trim(),
    quantity: Number($('mvQty').value), reference: $('mvRef').value.trim() || 'WEB',
  };
  const r = await call('/movements', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  if (r.status === 201) {
    $('mvOut').className = 'out ok';
    $('mvOut').textContent = `Posted: movement ${r.body.movement}, new quantity ${nf.format(r.body.newQuantity)} (HTTP 201).`;
    await load();
  } else {
    $('mvOut').className = 'out err';
    $('mvOut').textContent = `Rejected (HTTP ${r.status}${r.body.sqlstate ? ', SQLSTATE ' + r.body.sqlstate : ''}): ${r.body.error}. Nothing was changed.`;
  }
}

// ---- wiring ---------------------------------------------------------------
['fWhs', 'fReorder', 'fText'].forEach((id) => $(id).addEventListener('input', render));
$('refresh').addEventListener('click', load);
$('rows').addEventListener('click', (e) => { const tr = e.target.closest('tr[data-item]'); if (tr) inquiry(tr.dataset.item); });
$('rows').addEventListener('keydown', (e) => { const tr = e.target.closest('tr[data-item]'); if (tr && e.key === 'Enter') inquiry(tr.dataset.item); });
$('inqForm').addEventListener('submit', (e) => { e.preventDefault(); inquiry($('inqItem').value.trim().toUpperCase()); });
$('mvForm').addEventListener('submit', post);
$('theme').addEventListener('click', () => {
  const root = document.documentElement;
  const dark = root.dataset.theme ? root.dataset.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
  root.dataset.theme = dark ? 'light' : 'dark';
});
const q = new URLSearchParams(location.search);
if (q.get('theme')) document.documentElement.dataset.theme = q.get('theme');
health();
load().then(() => { if (q.get('ask')) inquiry(q.get('ask')); });
