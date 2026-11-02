// Sends the "points added" SMS for one row of public.sms_outbox.
//
// Called only by the database (dispatch_points_sms trigger, via pg_net) with
// { id } and an x-points-sms-secret header. The secret lives in Vault and is
// checked with points_sms_secret_ok(), which only service_role may execute.
// Deploy with --no-verify-jwt: the caller is the database, not a signed-in user.
//
// Twilio Messaging (not Verify — Verify can only send OTP codes). Set these as
// Edge Function secrets in the Supabase dashboard:
//   TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_MESSAGING_SERVICE_SID
// Until they are set, rows are marked failed with "Twilio sender not configured".

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const TWILIO_ACCOUNT_SID = Deno.env.get('TWILIO_ACCOUNT_SID');
const TWILIO_AUTH_TOKEN = Deno.env.get('TWILIO_AUTH_TOKEN');
const TWILIO_MESSAGING_SERVICE_SID = Deno.env.get('TWILIO_MESSAGING_SERVICE_SID');

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

// auth.users stores phones without the "+" (e.g. 60123456789) — Twilio needs E.164.
function toE164(phone: string) {
  return '+' + phone.replace(/[^\d]/g, '');
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const secret = req.headers.get('x-points-sms-secret') || '';
  const { data: ok } = await db.rpc('points_sms_secret_ok', { p_secret: secret });
  if (!ok) return json({ error: 'Forbidden' }, 403);

  const { id } = await req.json().catch(() => ({}));
  if (!id) return json({ error: 'Missing id' }, 400);

  // Claim the row (queued -> failed placeholder) so a repeated call can't double-send.
  const { data: row } = await db.from('sms_outbox')
    .update({ status: 'failed', error: 'sending' })
    .eq('id', id).eq('status', 'queued')
    .select('id, phone, body').maybeSingle();
  if (!row) return json({ error: 'Not queued' }, 409);

  const finish = (fields: Record<string, unknown>) =>
    db.from('sms_outbox').update(fields).eq('id', row.id);

  if (!TWILIO_ACCOUNT_SID || !TWILIO_AUTH_TOKEN || !TWILIO_MESSAGING_SERVICE_SID) {
    await finish({ status: 'failed', error: 'Twilio sender not configured' });
    return json({ error: 'Twilio sender not configured' }, 500);
  }

  const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`, {
    method: 'POST',
    headers: {
      Authorization: 'Basic ' + btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`),
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      To: toE164(row.phone),
      MessagingServiceSid: TWILIO_MESSAGING_SERVICE_SID,
      Body: row.body,
    }),
  });
  const out = await res.json().catch(() => ({}));

  if (!res.ok) {
    await finish({ status: 'failed', error: `Twilio ${res.status}: ${out.message || 'error'}`.slice(0, 500) });
    return json({ error: out.message || 'Twilio error' }, 502);
  }
  await finish({ status: 'sent', error: null, twilio_sid: out.sid, sent_at: new Date().toISOString() });
  return json({ sent: true, sid: out.sid }, 200);
});
