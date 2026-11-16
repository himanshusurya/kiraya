import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { freshDb, as, roomId, tenantLogin, num, OWNER, OWNER2 } from './harness.mjs';
import { parseCsv, toEntries, summary } from '../../scripts/import/import-history.mjs';

const onboard = (db, payload) =>
  as(db, OWNER, async ({ one }) => (await one('select onboard_tenant($1::jsonb) id', [JSON.stringify(payload)])).id);

const balance = async (db, t) => num((await db.query('select tenancy_balance($1) b', [t])).rows[0].b);
const bills = async (db, t) =>
  (await db.query(`select b.*, (select json_agg(l order by l.sort) from bill_line l where l.bill_id = b.id) lines
                   from bill b where tenancy_id = $1 order by cycle_start`, [t])).rows;

test('migrations load and seed creates 16 rooms + settings', async () => {
  const db = await freshDb();
  assert.equal(num((await db.query('select count(*) c from room')).rows[0].c), 16);
  const s = await as(db, OWNER, ({ one }) => one('select current_settings() s'));
  assert.equal(num(s.s.electricity_rate), 12);
  assert.equal(num(s.s.cleaning_charge), 500);
});

test('rent cycle anchored on move-in date, month-end clamp', async () => {
  const db = await freshDb();
  const q = async (a, b) => (await db.query('select cycle_end_of($1::date, $2::date)::text e', [a, b])).rows[0].e;
  assert.equal(await q('2026-01-15', '2026-01-15'), '2026-02-14');
  assert.equal(await q('2026-01-15', '2026-02-15'), '2026-03-14');
  assert.equal(await q('2026-01-31', '2026-01-31'), '2026-02-27');
  assert.equal(await q('2026-01-31', '2026-02-28'), '2026-03-30');
  assert.equal(await q('2026-01-31', '2026-03-31'), '2026-04-29');
  assert.equal(await q('2026-01-01', '2026-02-01'), '2026-02-28');
});

test('full monthly flow: bill, split payment, credit carry-forward, rate change, tenant claim', async () => {
  const db = await freshDb();
  const r101 = await roomId(db, '101');
  const t = await onboard(db, {
    room_id: r101, start_date: '2026-01-15', monthly_rent: 2500, advance_amount: 3000, move_in_reading: 1000,
    tenants: [{ full_name: 'Ravi Kumar', phone: '9876543210', caste: 'X', religion: 'Y', app_access: true }],
  });
  assert.equal((await db.query('select status from room where id=$1', [r101])).rows[0].status, 'OCCUPIED');

  // Common reading day (1st)
  await as(db, OWNER, ({ q }) => q(`select add_readings('2026-02-01', $1::jsonb)`, [JSON.stringify([{ room_id: r101, value: 1040 }])]));
  // Nothing due before cycle end
  assert.equal((await as(db, OWNER, ({ one }) => one(`select generate_due_bills('2026-02-13') n`))).n, 0);
  assert.equal((await as(db, OWNER, ({ one }) => one(`select generate_due_bills('2026-02-14') n`))).n, 1);
  let [b1] = await bills(db, t);
  assert.equal(b1.status, 'DRAFT');
  assert.equal(num(b1.total), 2980); // 2500 + 40 units * 12
  assert.equal(await balance(db, t), 0); // draft not on ledger
  await as(db, OWNER2, ({ q }) => q('select issue_all_drafts()'));
  assert.equal(await balance(db, t), 2980);
  [b1] = await bills(db, t);
  assert.equal(b1.due_date.toISOString().slice(0, 10), '2026-02-19');

  // Split payment, slightly more than due -> credit carries forward
  const splits = [{ mode: 'CASH', amount: 2000 }, { mode: 'PHONEPE', amount: 1000, ref: 'T123' }];
  const p1 = await as(db, OWNER, ({ one }) =>
    one(`select record_payment($1, '2026-02-16', $2::jsonb, null, 'k1') id`, [t, JSON.stringify(splits)]));
  // idempotent retry returns same payment
  const p1b = await as(db, OWNER, ({ one }) =>
    one(`select record_payment($1, '2026-02-16', $2::jsonb, null, 'k1') id`, [t, JSON.stringify(splits)]));
  assert.equal(p1.id, p1b.id);
  assert.equal(await balance(db, t), -20);
  assert.equal((await bills(db, t))[0].status, 'PAID');

  // Rate change effective 20 Feb applies to the 1 March reading
  await as(db, OWNER, ({ q }) => q(`select update_setting('electricity_rate', '10'::jsonb, '2026-02-20')`));
  await as(db, OWNER, ({ q }) => q(`select add_readings('2026-03-01', $1::jsonb)`, [JSON.stringify([{ room_id: r101, value: 1100 }])]));
  await as(db, OWNER, ({ q }) => q(`select generate_due_bills('2026-03-20'); select issue_all_drafts();`));
  const b2 = (await bills(db, t))[1];
  assert.equal(b2.cycle_start.toISOString().slice(0, 10), '2026-02-15');
  assert.equal(num(b2.opening_balance), -20);
  assert.equal(num(b2.total), 3100); // 2500 + 60*10
  assert.equal(await balance(db, t), 3080);

  // Tenant "I paid" -> pending until owner confirms
  const [occ] = (await db.query('select tenant_id from occupant where tenancy_id=$1', [t])).rows;
  const tu = await tenantLogin(db, occ.tenant_id);
  const claim = await as(db, tu, ({ one }) =>
    one(`select claim_payment($1, '2026-03-16', 3080, 'GPAY', 'UTR9', 'paid', null, 'c1') id`, [t]));
  assert.equal(await balance(db, t), 3080);
  const pend = await as(db, OWNER, ({ q }) => q(`select * from v_tenancy_summary where tenancy_id=$1`, [t]));
  assert.equal(num(pend[0].pending_claims), 1);
  await as(db, OWNER, ({ q }) => q('select confirm_payment($1, true)', [claim.id]));
  assert.equal(await balance(db, t), 0);
  assert.ok((await bills(db, t)).every((b) => b.status === 'PAID'));

  // Void (undo) a payment re-opens dues
  await as(db, OWNER, ({ q }) => q(`select void_payment($1, 'wrong entry')`, [claim.id]));
  assert.equal(await balance(db, t), 3080);
  assert.equal((await bills(db, t))[1].status, 'PARTIAL');
});

test('late meter reading: rent-only bill, units roll to next bill; recurring + one-off charges', async () => {
  const db = await freshDb();
  const r = await roomId(db, '201');
  const t = await onboard(db, {
    room_id: r, start_date: '2026-03-10', monthly_rent: 2800, move_in_reading: 500,
    tenants: [{ full_name: 'Sunil' }], charges: [{ label: 'Fan', amount: 420 }],
  });
  await as(db, OWNER, async ({ q }) => {
    await q(`select add_charge($1, 'Medicine', -120, 'ONE_OFF', '2026-03-20')`, [t]);
    await q(`select generate_due_bills('2026-04-09'); select issue_all_drafts();`);
  });
  let bs = await bills(db, t);
  assert.equal(bs.length, 1);
  assert.deepEqual(bs[0].lines.map((l) => l.kind), ['RENT', 'CHARGE', 'CHARGE']);
  assert.equal(num(bs[0].total), 2800 + 420 - 120);

  await as(db, OWNER, ({ q }) => q(`select add_readings('2026-04-01', $1::jsonb)`, [JSON.stringify([{ room_id: r, value: 530 }])]));
  await as(db, OWNER, ({ q }) => q(`select add_readings('2026-05-01', $1::jsonb)`, [JSON.stringify([{ room_id: r, value: 580 }])]));
  await as(db, OWNER, ({ q }) => q(`select generate_due_bills('2026-05-09'); select issue_all_drafts();`));
  bs = await bills(db, t);
  const elec = bs[1].lines.find((l) => l.kind === 'ELECTRICITY');
  assert.equal(num(elec.qty), 80); // 500 -> 580 (latest reading <= bill date)
  assert.equal(bs[1].lines.filter((l) => l.kind === 'CHARGE').length, 1); // one-off not repeated

  // Reading going backwards is refused unless forced
  await assert.rejects(as(db, OWNER, ({ q }) =>
    q(`select add_readings('2026-06-01', $1::jsonb)`, [JSON.stringify([{ room_id: r, value: 100 }])])), /less than last reading/);
});

test('discard draft restores cycle and releases reading', async () => {
  const db = await freshDb();
  const r = await roomId(db, '102');
  const t = await onboard(db, { room_id: r, start_date: '2026-01-01', monthly_rent: 2000, move_in_reading: 10, tenants: [{ full_name: 'A' }] });
  await as(db, OWNER, ({ q }) => q(`select add_readings('2026-01-31', $1::jsonb)`, [JSON.stringify([{ room_id: r, value: 30 }])]));
  await as(db, OWNER, ({ q }) => q(`select generate_due_bills('2026-01-31')`));
  const [b] = await bills(db, t);
  await as(db, OWNER, ({ q }) => q('select discard_draft_bill($1)', [b.id]));
  await as(db, OWNER, ({ q }) => q(`select generate_due_bills('2026-01-31')`));
  const again = await bills(db, t);
  assert.equal(again.length, 1);
  assert.equal(num(again[0].total), 2000 + 20 * 12);
});

test('move-out: notice, pro-rated rent, final reading, cleaning, shortfall, advance used, refund', async () => {
  const db = await freshDb();
  const r = await roomId(db, '103');
  const t = await onboard(db, {
    room_id: r, start_date: '2026-01-10', monthly_rent: 3000, advance_amount: 4000, move_in_reading: 200,
    tenants: [{ full_name: 'Mohan', app_access: true }],
  });
  await as(db, OWNER, ({ q }) => q(`select generate_due_bills('2026-02-09'); select issue_all_drafts();`));
  const info = await as(db, OWNER, ({ one }) => one(`select give_notice($1, '2026-02-24', '2026-02-10') i`, [t]));
  assert.equal(info.i.short_by_days, 16);
  // cron must not bill the cycle containing the leave date
  await as(db, OWNER, ({ q }) => q(`select generate_due_bills('2026-03-15')`));
  assert.equal((await bills(db, t)).length, 1);

  const s = await as(db, OWNER, ({ one }) => one(
    `select settle_move_out($1, '2026-02-24', 260, 600, null, '[{"label":"Broken tap","amount":150}]'::jsonb) s`, [t]));
  const fin = (await bills(db, t)).at(-1);
  assert.equal(fin.is_final, true);
  const rent = fin.lines.find((l) => l.kind === 'RENT');
  assert.equal(num(rent.qty), 15); // 10 Feb .. 24 Feb
  assert.equal(num(rent.amount), Math.round(3000 * 15 / 28));
  assert.equal(num(fin.lines.find((l) => l.kind === 'ELECTRICITY').amount), 60 * 12);
  assert.equal(num(fin.lines.find((l) => l.kind === 'CLEANING').amount), 500);
  const finalTotal = Math.round(3000 * 15 / 28) + 720 + 500 + 600 + 150;
  assert.equal(num(fin.total), finalTotal);
  // dues = first bill 3000 + final; advance 4000 covers part
  const dues = 3000 + finalTotal;
  assert.equal(num(s.s.advance_used), Math.min(4000, dues));
  assert.equal(num(s.s.still_due), Math.max(dues - 4000, 0));
  assert.equal(s.s.outcome, dues > 4000 ? 'DUE_PENDING' : 'REFUNDED');
  assert.equal((await db.query('select status from room where id=$1', [r])).rows[0].status, 'VACANT');
  assert.equal(num((await db.query('select advance_held($1) a', [t])).rows[0].a), 0);
});

test('move-out with credit refunds advance + extra; absconded writes off', async () => {
  const db = await freshDb();
  const r = await roomId(db, '104');
  const t = await onboard(db, { room_id: r, start_date: '2026-01-01', monthly_rent: 2000, advance_amount: 2000, tenants: [{ full_name: 'B' }] });
  await as(db, OWNER, ({ q }) => q(`select record_payment($1, '2026-01-05', '[{"mode":"CASH","amount":5000}]'::jsonb)`, [t]));
  const s = await as(db, OWNER, ({ one }) => one(`select settle_move_out($1, '2026-01-31', null, 0, 500) s`, [t]));
  // Jan full cycle 2000 + cleaning 500 = 2500 due; paid 5000 -> 2500 extra + 2000 advance back
  assert.equal(num(s.s.refund), 4500);
  assert.equal(s.s.outcome, 'REFUNDED');
  assert.equal(await balance(db, t), 0);

  const r2 = await roomId(db, '105');
  const t2 = await onboard(db, { room_id: r2, start_date: '2026-01-01', monthly_rent: 2500, advance_amount: 1700, tenants: [{ full_name: 'C' }] });
  const s2 = await as(db, OWNER, ({ one }) => one(`select settle_move_out($1, '2026-03-05', null, 0, 0, '[]', true) s`, [t2]));
  assert.equal(s2.s.outcome, 'WRITTEN_OFF');
  assert.equal(await balance(db, t2), 0);
  assert.equal((await db.query('select status from tenancy where id=$1', [t2])).rows[0].status, 'ABSCONDED');
});

test('room shift moves balance, advance, recurring charges; new anchor', async () => {
  const db = await freshDb();
  const a = await roomId(db, '106');
  const bRoom = await roomId(db, '107');
  const t = await onboard(db, {
    room_id: a, start_date: '2026-01-05', monthly_rent: 2400, advance_amount: 2400, move_in_reading: 0,
    tenants: [{ full_name: 'D' }], charges: [{ label: 'Fan', amount: 420 }],
  });
  await as(db, OWNER, ({ q }) => q(`select generate_due_bills('2026-02-04'); select issue_all_drafts();`));
  const nt = (await as(db, OWNER, ({ one }) => one(`select shift_room($1, $2, '2026-02-20', 50, 900, 2600) id`, [t, bRoom]))).id;
  const old = await bills(db, t);
  assert.equal(old.length, 2);
  const fin = old[1];
  assert.equal(num(fin.lines.find((l) => l.kind === 'RENT').qty), 15); // 5 Feb .. 19 Feb
  assert.equal(await balance(db, t), 0);
  const moved = 2400 + 420 + num(fin.total);
  assert.equal(await balance(db, nt), moved);
  assert.equal(num((await db.query('select advance_held($1) a', [nt])).rows[0].a), 2400);
  const ntRow = (await db.query('select * from tenancy where id=$1', [nt])).rows[0];
  assert.equal(ntRow.start_date.toISOString().slice(0, 10), '2026-02-20');
  assert.equal(num(ntRow.monthly_rent), 2600);
  assert.equal(num((await db.query(`select count(*) c from charge where tenancy_id=$1 and kind='RECURRING'`, [nt])).rows[0].c), 1);
  await as(db, OWNER, ({ q }) => q(`select add_readings('2026-03-01', $1::jsonb)`, [JSON.stringify([{ room_id: bRoom, value: 930 }])]));
  await as(db, OWNER, ({ q }) => q(`select generate_due_bills('2026-03-19')`));
  const nb = (await bills(db, nt))[0];
  assert.equal(num(nb.lines.find((l) => l.kind === 'ELECTRICITY').qty), 30);
});

test('security: tenant isolation, no direct money writes, append-only ledger', async () => {
  const db = await freshDb();
  const t1 = await onboard(db, { room_id: await roomId(db, '101'), start_date: '2026-01-01', monthly_rent: 2000, tenants: [{ full_name: 'T1', app_access: true }, { full_name: 'T1b', app_access: true }] });
  const t2 = await onboard(db, { room_id: await roomId(db, '102'), start_date: '2026-01-01', monthly_rent: 2000, tenants: [{ full_name: 'T2', app_access: true }] });
  await as(db, OWNER, ({ q }) => q(`select generate_due_bills('2026-02-28'); select issue_all_drafts();`));
  const occ = (await db.query('select tenant_id from occupant where tenancy_id=$1 order by is_primary', [t1])).rows;
  const roommate = await tenantLogin(db, occ[0].tenant_id); // co-occupant, not primary

  await as(db, roommate, async ({ q }) => {
    const b = await q('select tenancy_id from bill');
    assert.ok(b.length === 2 && b.every((x) => x.tenancy_id === t1), 'co-occupant sees room bills only');
    assert.equal((await q('select * from tenancy')).length, 1);
    assert.equal((await q('select * from tenant')).length, 1, 'sees only own personal data');
    assert.equal((await q('select * from v_room_board')).length, 1);
    const sum = await q('select tenancy_id, balance, primary_name from v_tenancy_summary');
    assert.equal(sum.length, 1, 'co-occupant sees own tenancy summary');
    assert.equal(sum[0].tenancy_id, t1);
    assert.equal(num(sum[0].balance), 4000);
    assert.equal(sum[0].primary_name, null, "primary tenant's personal row stays hidden");
    assert.equal((await q('select tenancy_id from v_room_board where tenancy_id is not null')).length, 1);
    assert.equal((await q('select * from setting')).length, 0);
  });
  await assert.rejects(as(db, roommate, ({ q }) => q(`select record_payment($1, null, '[{"mode":"CASH","amount":1}]')`, [t1])), /owner|Not allowed/i);
  await assert.rejects(as(db, roommate, ({ q }) => q(`select claim_payment($1, null, 10, 'CASH')`, [t2])), /Not allowed/);
  await assert.rejects(as(db, roommate, ({ q }) =>
    q(`insert into ledger_entry (property_id, tenancy_id, entry_date, kind, credit) select property_id, id, now(), 'PAYMENT', 9999 from tenancy`)), /permission denied/);
  await assert.rejects(as(db, roommate, ({ q }) => q(`select _post(null, null, 'PAYMENT', 1, '')`)), /permission denied/);
  await assert.rejects(as(db, 'anon', ({ q }) => q('select * from tenant')), /permission denied/);
  await assert.rejects(as(db, OWNER, ({ q }) => q(`update ledger_entry set debit = 0`)), /permission denied|append-only/);
  await assert.rejects(db.query(`delete from ledger_entry`), /append-only/);
  // tenant can raise a complaint for own room, not for others
  await as(db, roommate, ({ q }) => q(`insert into complaint (property_id, tenancy_id, text, raised_by) select property_id, $1, 'No water', $2 from tenancy where id=$1`, [t1, roommate]));
  await assert.rejects(as(db, roommate, ({ q }) => q(`insert into complaint (property_id, tenancy_id, text, raised_by) values ('00000000-0000-0000-0000-000000000001', $1, 'x', $2)`, [t2, roommate])), /row-level security/);
  // owner sees everything; audit trail records who did it
  await as(db, OWNER, async ({ q }) => {
    assert.equal((await q('select * from tenancy')).length, 2);
    assert.ok((await q(`select * from audit_log where entity='bill' and actor=$1`, [OWNER])).length > 0);
  });
});

test('import history replays paper ledger; cron as service role', async () => {
  const db = await freshDb();
  const t = await onboard(db, { room_id: await roomId(db, '203'), start_date: '2026-03-01', monthly_rent: 2500, tenants: [{ full_name: 'E' }] });
  const entries = [
    { type: 'OPENING', date: '2026-03-01', amount: 300 },
    { type: 'BILL', date: '2026-03-31', cycle_start: '2026-03-01', cycle_end: '2026-03-31', lines: [{ kind: 'RENT', amount: 2500 }, { kind: 'ELECTRICITY', qty: 30, rate: 12, amount: 360 }] },
    { type: 'PAYMENT', date: '2026-04-05', amount: 3200, mode: 'PHONEPE' },
    { type: 'ADJUSTMENT', date: '2026-04-05', amount: -44, note: 'electricity bill adjustment' },
  ];
  await as(db, OWNER, ({ q }) => q('select import_history($1, $2::jsonb)', [t, JSON.stringify(entries)]));
  assert.equal(await balance(db, t), 300 + 2860 - 3200 - 44);
  assert.equal((await db.query('select next_cycle_start::text d from tenancy where id=$1', [t])).rows[0].d, '2026-04-01');
  await assert.rejects(as(db, OWNER, ({ q }) => q(`select cron_daily('2026-05-01')`)), /permission denied|service role only/);
  const r = await as(db, 'service', ({ one }) => one(`select cron_daily('2026-05-01') r`));
  assert.equal(r.r.bills_created, 1); // April cycle
});

test('CSV import template round-trips through import_history', async () => {
  const db = await freshDb();
  const t = await onboard(db, { room_id: await roomId(db, '101'), start_date: '2026-03-15', monthly_rent: 2500, tenants: [{ full_name: 'F' }] });
  const csv = readFileSync(new URL('../../scripts/import/history.template.csv', import.meta.url), 'utf8');
  const entries = toEntries(parseCsv(csv)).get('101');
  assert.equal(entries.length, 5);
  const expected = summary(entries).balance;
  assert.equal(expected, 3460 + 1100 - 3500);
  await as(db, OWNER, ({ q }) => q('select import_history($1, $2::jsonb)', [t, JSON.stringify(entries)]));
  assert.equal(await balance(db, t), expected);
  assert.equal((await db.query('select next_cycle_start::text d from tenancy where id=$1', [t])).rows[0].d, '2026-04-15');
});
