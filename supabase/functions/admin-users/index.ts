// Handles privileged auth admin operations (create/delete/update user) that require
// the service_role key. The key never leaves this function — it is injected by the
// Supabase Edge Function runtime as an env var, never shipped to the browser.
//
// Every request must carry the caller's own session access token in the
// Authorization header. That token is used to look up the caller and confirm
// profiles.is_admin OR profiles.is_staff before any privileged action runs.
//
// Staff may create accounts and update/delete plain member accounts, but may not
// touch (update or delete) any account that is itself an admin or staff account —
// only a full admin can. This mirrors the profiles-table RLS policy split, but has
// to be enforced here too since these are auth-level operations (email/password/
// delete), not profile-row edits, so table RLS alone can't cover it.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// Restrict to your real site origin(s) in production.
// Add a custom domain here too if/when you put one in front of Netlify.
const ALLOWED_ORIGINS = [
  'https://thetravelchapter.netlify.app',
];

function corsHeaders(origin: string | null) {
  const allow = origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allow,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

function json(body: unknown, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  const origin = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(origin) });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405, origin);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Missing Authorization header' }, 401, origin);
  const token = authHeader.slice('Bearer '.length);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: { user }, error: userErr } = await admin.auth.getUser(token);
  if (userErr || !user) return json({ error: 'Invalid or expired session' }, 401, origin);

  const { data: profile, error: profErr } = await admin
    .from('profiles').select('is_admin, is_staff').eq('id', user.id).single();
  if (profErr || !(profile?.is_admin || profile?.is_staff)) return json({ error: 'Admins only' }, 403, origin);
  const isFullAdmin = !!profile.is_admin;

  // Staff can't touch an existing admin-or-staff account (email/password/delete) —
  // only a full admin can. No-op for full admins (they skip this check entirely).
  async function blockedByStaffTargetingAdmin(targetId: string) {
    if (isFullAdmin) return false;
    const { data: target } = await admin.from('profiles').select('is_admin, is_staff').eq('id', targetId).single();
    return !!(target?.is_admin || target?.is_staff);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON body' }, 400, origin);
  }
  const { action } = body;

  if (action === 'create') {
    const { email, password, user_metadata } = body as {
      email: string; password: string; user_metadata?: Record<string, unknown>;
    };
    if (!email || !password) return json({ error: 'email and password are required' }, 400, origin);
    const { data, error } = await admin.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata,
    });
    if (error) return json({ error: error.message }, 400, origin);
    return json({ user: data.user }, 200, origin);
  }

  if (action === 'delete') {
    const { id } = body as { id: string };
    if (!id) return json({ error: 'id is required' }, 400, origin);
    if (id === user.id) return json({ error: "You can't delete your own account" }, 400, origin);
    if (await blockedByStaffTargetingAdmin(id)) return json({ error: 'Only admins can modify admin or staff accounts' }, 403, origin);
    const { error } = await admin.auth.admin.deleteUser(id);
    if (error) return json({ error: error.message }, 400, origin);
    return json({ ok: true }, 200, origin);
  }

  if (action === 'update') {
    const { id, email, password } = body as { id: string; email?: string; password?: string };
    if (!id) return json({ error: 'id is required' }, 400, origin);
    if (await blockedByStaffTargetingAdmin(id)) return json({ error: 'Only admins can modify admin or staff accounts' }, 403, origin);
    const updates: Record<string, unknown> = {};
    if (email) { updates.email = email; updates.email_confirm = true; }
    if (password) updates.password = password;
    if (Object.keys(updates).length === 0) return json({ error: 'Nothing to update' }, 400, origin);
    const { error } = await admin.auth.admin.updateUserById(id, updates);
    if (error) return json({ error: error.message }, 400, origin);
    return json({ ok: true }, 200, origin);
  }

  return json({ error: 'Unknown action' }, 400, origin);
});
