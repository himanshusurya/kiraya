// Test harness: runs the real migrations inside PGlite (Postgres compiled to WASM)
// with a minimal stand-in for Supabase's auth/storage schemas and roles.
import { PGlite } from '@electric-sql/pglite';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

const SUPABASE_STUB = `
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create table auth.users (id uuid primary key, email text);
create function auth.jwt() returns jsonb language sql stable as
  $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub', '')::uuid $$;
create function auth.role() returns text language sql stable as $$ select auth.jwt()->>'role' $$;
create schema storage;
create table storage.buckets (id text primary key, name text, public boolean);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as
  $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
grant usage on schema public, auth, storage to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
`;

export const PROPERTY = '00000000-0000-0000-0000-000000000001';
export const OWNER = '11111111-1111-1111-1111-111111111111';
export const OWNER2 = '11111111-1111-1111-1111-222222222222';

export async function freshDb() {
  const db = await PGlite.create();
  await db.exec(SUPABASE_STUB);
  const migDir = join(root, 'migrations');
  for (const f of readdirSync(migDir).filter((f) => f.endsWith('.sql')).sort()) {
    try {
      await db.exec(readFileSync(join(migDir, f), 'utf8'));
    } catch (e) {
      throw new Error(`${f}: ${e.message}`);
    }
  }
  await db.exec(readFileSync(join(root, 'seed.sql'), 'utf8'));
  await db.exec(`
    insert into auth.users (id) values ('${OWNER}'), ('${OWNER2}');
    insert into app_user (id, property_id, role, name) values
      ('${OWNER}', '${PROPERTY}', 'OWNER', 'Owner'),
      ('${OWNER2}', '${PROPERTY}', 'OWNER', 'Himanshu');
  `);
  return db;
}

// Run fn as a given Supabase identity inside a transaction (role + JWT claims).
export async function as(db, who, fn) {
  return db.transaction(async (tx) => {
    if (who === 'service') {
      await tx.exec(`set local role service_role; select set_config('request.jwt.claims', '{"role":"service_role"}', true);`);
    } else if (who === 'anon') {
      await tx.exec(`set local role anon; select set_config('request.jwt.claims', '{"role":"anon"}', true);`);
    } else {
      await tx.exec(`set local role authenticated;
        select set_config('request.jwt.claims', '${JSON.stringify({ sub: who, role: 'authenticated' })}', true);`);
    }
    const q = async (sql, params) => params ? (await tx.query(sql, params)).rows : (await tx.exec(sql)).at(-1).rows;
    const one = async (sql, params) => (await q(sql, params))[0];
    return fn({ q, one, tx });
  });
}

export async function roomId(db, number) {
  return (await db.query('select id from room where number = $1', [number])).rows[0].id;
}

// Creates a TENANT login linked to the given tenant (what the edge function does).
export async function tenantLogin(db, tenantId) {
  const uid = (await db.query('select gen_random_uuid() id')).rows[0].id;
  await db.query('insert into auth.users (id) values ($1)', [uid]);
  await db.query(`insert into app_user (id, property_id, role, name, tenant_id)
                  select $1, property_id, 'TENANT', full_name, id from tenant where id = $2`, [uid, tenantId]);
  return uid;
}

export const num = (v) => (v === null || v === undefined ? v : Number(v));
