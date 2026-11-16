// manage-login: owner-only management of phone + PIN logins (HLD D11/D18).
// Logins are Supabase email/password users with a synthetic email derived from the
// phone number, so no paid SMS/OTP provider is needed.
//
// POST { action: "create_tenant_login", tenant_id, pin }
// POST { action: "reset_pin", phone, pin }
// POST { action: "set_active", phone, active }
// POST { action: "create_owner", name, phone, pin }   (first owner: needs service key)
import { createClient } from 'npm:@supabase/supabase-js@2';

const URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(URL, SERVICE, { auth: { persistSession: false } });

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

export const phoneToEmail = (phone: string) => `p${normalizePhone(phone)}@login.kiraya.app`;
export function normalizePhone(phone: string) {
  const d = String(phone ?? '').replace(/\D/g, '');
  return d.length > 10 ? d.slice(-10) : d;
}
const validPin = (pin: string) => /^\d{6}$/.test(String(pin ?? ''));

async function caller(req: Request) {
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!token) return null;
  if (token === SERVICE) return { service: true } as const;
  const { data } = await admin.auth.getUser(token);
  if (!data.user) return null;
  const { data: me } = await admin.from('app_user').select('*').eq('id', data.user.id).eq('active', true).single();
  return me ? { service: false, me } as const : null;
}

async function findUserIdByPhone(phone: string) {
  const { data } = await admin.from('app_user').select('id').eq('phone', normalizePhone(phone)).maybeSingle();
  return data?.id as string | undefined;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const who = await caller(req);
    if (!who) return json({ error: 'Please log in again' }, 401);
    const body = await req.json();
    const isOwner = who.service || who.me.role === 'OWNER';

    if (body.action === 'create_owner') {
      if (!isOwner) return json({ error: 'Only the owner can do this' }, 403);
      if (!validPin(body.pin)) return json({ error: 'PIN must be 6 digits' }, 400);
      const phone = normalizePhone(body.phone);
      const property_id = who.service
        ? (await admin.from('property').select('id').order('created_at').limit(1).single()).data!.id
        : who.me.property_id;
      const { data, error } = await admin.auth.admin.createUser({
        email: phoneToEmail(phone), password: body.pin, email_confirm: true, user_metadata: { phone },
      });
      if (error) return json({ error: error.message }, 400);
      const { error: e2 } = await admin.from('app_user').insert({
        id: data.user.id, property_id, role: 'OWNER', name: body.name ?? 'Owner', phone,
      });
      if (e2) return json({ error: e2.message }, 400);
      return json({ ok: true, user_id: data.user.id });
    }

    if (!isOwner) return json({ error: 'Only the owner can do this' }, 403);

    if (body.action === 'create_tenant_login') {
      if (!validPin(body.pin)) return json({ error: 'PIN must be 6 digits' }, 400);
      const { data: t } = await admin.from('tenant').select('*').eq('id', body.tenant_id).single();
      if (!t || (!who.service && t.property_id !== who.me.property_id)) return json({ error: 'Person not found' }, 404);
      const phone = normalizePhone(body.phone ?? t.phone);
      if (phone.length !== 10) return json({ error: 'A 10-digit mobile number is needed' }, 400);
      const existing = await findUserIdByPhone(phone);
      if (existing) return json({ error: 'This mobile number already has a login' }, 409);
      const { data, error } = await admin.auth.admin.createUser({
        email: phoneToEmail(phone), password: body.pin, email_confirm: true, user_metadata: { phone },
      });
      if (error) return json({ error: error.message }, 400);
      const { error: e2 } = await admin.from('app_user').insert({
        id: data.user.id, property_id: t.property_id, role: 'TENANT', name: t.full_name, phone, tenant_id: t.id,
      });
      if (e2) return json({ error: e2.message }, 400);
      // give app access on all live tenancies of this person
      await admin.from('occupant').update({ app_access: true }).eq('tenant_id', t.id).is('left_on', null);
      return json({ ok: true, user_id: data.user.id, phone });
    }

    if (body.action === 'reset_pin') {
      if (!validPin(body.pin)) return json({ error: 'PIN must be 6 digits' }, 400);
      const id = await findUserIdByPhone(body.phone);
      if (!id) return json({ error: 'No login for this number' }, 404);
      const { error } = await admin.auth.admin.updateUserById(id, { password: body.pin });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    if (body.action === 'set_active') {
      const id = await findUserIdByPhone(body.phone);
      if (!id) return json({ error: 'No login for this number' }, 404);
      if (!who.service && id === who.me.id) return json({ error: 'You cannot turn off your own login' }, 400);
      await admin.from('app_user').update({ active: !!body.active }).eq('id', id);
      await admin.auth.admin.updateUserById(id, { ban_duration: body.active ? 'none' : '876000h' });
      return json({ ok: true });
    }

    return json({ error: 'Unknown action' }, 400);
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
