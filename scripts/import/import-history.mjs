#!/usr/bin/env node
// Imports the old paper ledger (6 months) for tenants who are already added in the Owner app.
//
// 1. Add each current tenant in the Owner app first (room, move-in date, rent, advance).
// 2. Fill history.csv (see history.template.csv), one row per bill / payment / correction.
// 3. Dry run:   node scripts/import/import-history.mjs history.csv --dry-run
// 4. Import:    set SUPABASE_URL, SUPABASE_ANON_KEY, OWNER_PHONE, OWNER_PIN, then run without --dry-run.
//
// Columns: room,date,type,amount,mode,ref,note,cycle_start,cycle_end,rent,units,rate,other_label,other_amount
//   type BILL       -> rent + units*rate + other_amount (amount column ignored)
//   type PAYMENT    -> amount, mode (CASH|PHONEPE|GPAY|UPI_OTHER|BANK), ref
//   type ADJUSTMENT -> amount (+ adds to dues, - reduces), note
//   type OPENING    -> amount carried over from before the 6 months
import { readFileSync } from 'node:fs';

export function parseCsv(text) {
  const rows = [];
  let row = [], field = '', quoted = false;
  const endRow = () => {
    row.push(field);
    field = '';
    if (row.some((f) => f.trim() !== '')) rows.push(row);
    row = [];
  };
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++; }
      else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      endRow();
    } else field += c;
  }
  endRow();
  const [header, ...data] = rows;
  const keys = header.map((h) => h.trim().replace(/^\uFEFF/, '').toLowerCase());
  return data
    .filter((r) => !r[0].trim().startsWith('#'))
    .map((r) => Object.fromEntries(keys.map((k, i) => [k, (r[i] ?? '').trim()])));
}

const n = (v) => (v === '' || v == null ? null : Number(v));
const isoDate = (v, line) => {
  // accepts 2026-03-15, 15/03/2026 or 15-03-2026
  let m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
  if (m) return v;
  m = /^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$/.exec(v);
  if (!m) throw new Error(`line ${line}: bad date "${v}"`);
  return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`;
};

/** Converts CSV rows to Map(room -> import_history entries). */
export function toEntries(rows) {
  const byRoom = new Map();
  rows.forEach((r, i) => {
    const line = i + 2;
    const type = r.type.toUpperCase();
    const date = isoDate(r.date, line);
    let e;
    if (type === 'BILL') {
      const lines = [];
      if (n(r.rent)) lines.push({ kind: 'RENT', label: 'Rent', amount: n(r.rent) });
      if (n(r.units) != null) {
        const rate = n(r.rate) ?? 12;
        lines.push({ kind: 'ELECTRICITY', label: 'Electricity', qty: n(r.units), rate, amount: Math.round(n(r.units) * rate * 100) / 100 });
      }
      if (n(r.other_amount)) lines.push({ kind: 'CHARGE', label: r.other_label || 'Other', amount: n(r.other_amount) });
      if (!lines.length) throw new Error(`line ${line}: BILL has no rent/units/other`);
      e = { type, date, lines };
      if (r.cycle_start) e.cycle_start = isoDate(r.cycle_start, line);
      if (r.cycle_end) e.cycle_end = isoDate(r.cycle_end, line);
    } else if (type === 'PAYMENT') {
      if (!(n(r.amount) > 0)) throw new Error(`line ${line}: PAYMENT needs a positive amount`);
      const mode = (r.mode || 'CASH').toUpperCase();
      if (!['CASH', 'PHONEPE', 'GPAY', 'UPI_OTHER', 'BANK'].includes(mode)) throw new Error(`line ${line}: bad mode ${mode}`);
      e = { type, date, amount: n(r.amount), mode, ...(r.ref && { ref: r.ref }) };
    } else if (type === 'ADJUSTMENT' || type === 'OPENING') {
      if (!n(r.amount)) throw new Error(`line ${line}: ${type} needs an amount`);
      e = { type, date, amount: n(r.amount) };
    } else throw new Error(`line ${line}: unknown type "${r.type}"`);
    if (r.note) e.note = r.note;
    if (!byRoom.has(r.room)) byRoom.set(r.room, []);
    byRoom.get(r.room).push(e);
  });
  return byRoom;
}

export function summary(entries) {
  const billed = entries.filter((e) => e.type === 'BILL').reduce((s, e) => s + e.lines.reduce((a, l) => a + l.amount, 0), 0);
  const paid = entries.filter((e) => e.type === 'PAYMENT').reduce((s, e) => s + e.amount, 0);
  const other = entries.filter((e) => e.type !== 'BILL' && e.type !== 'PAYMENT').reduce((s, e) => s + e.amount, 0);
  return { billed, paid, other, balance: billed + other - paid };
}

async function main() {
  const [file, flag] = process.argv.slice(2);
  if (!file) throw new Error('usage: import-history.mjs <file.csv> [--dry-run]');
  const byRoom = toEntries(parseCsv(readFileSync(file, 'utf8')));
  if (flag === '--dry-run') {
    for (const [room, entries] of byRoom) {
      const s = summary(entries);
      console.log(`Room ${room}: ${entries.length} entries, billed ${s.billed}, paid ${s.paid}, other ${s.other}, balance ${s.balance}`);
    }
    return;
  }
  const { SUPABASE_URL: url, SUPABASE_ANON_KEY: key, OWNER_PHONE: phone, OWNER_PIN: pin } = process.env;
  if (!url || !key || !phone || !pin) throw new Error('Set SUPABASE_URL, SUPABASE_ANON_KEY, OWNER_PHONE, OWNER_PIN');
  const digits = phone.replace(/\D/g, '').slice(-10);
  const auth = await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: key, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: `p${digits}@login.kiraya.app`, password: pin }),
  }).then((r) => r.json());
  if (!auth.access_token) throw new Error(`Login failed: ${JSON.stringify(auth)}`);
  const h = { apikey: key, Authorization: `Bearer ${auth.access_token}`, 'Content-Type': 'application/json' };
  const board = await fetch(`${url}/rest/v1/v_room_board?select=number,tenancy_id`, { headers: h }).then((r) => r.json());
  for (const [room, entries] of byRoom) {
    const t = board.find((b) => b.number === room)?.tenancy_id;
    if (!t) {
      console.error(`Room ${room}: no current tenant - add them in the app first. Skipped.`);
      continue;
    }
    const res = await fetch(`${url}/rest/v1/rpc/import_history`, {
      method: 'POST',
      headers: h,
      body: JSON.stringify({ p_tenancy: t, p_entries: entries }),
    });
    console.log(`Room ${room}: ${res.ok ? `imported ${await res.text()} entries` : `FAILED ${await res.text()}`}`);
  }
}

if (process.argv[1]?.endsWith('import-history.mjs')) {
  main().catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}
