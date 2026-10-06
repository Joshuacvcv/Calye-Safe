// Calye-Safe — auth-gate Edge Function
//
// WHAT: the only server-side step in front of password login.
//   1. Verifies the Cloudflare Turnstile token with Cloudflare (secret key
//      stays here — never in the repo, never in the browser).
//   2. Counts recent FAILED attempts per email (10 / 15 min) and per IP
//      (30 / 15 min) in public.login_attempts. Over the limit -> 429.
//   3. mode 'login': performs signInWithPassword itself and returns the
//      session, so skipping the widget/token can never bypass the gate.
//      mode 'check': token + rate-limit verification only (used by signup).
//
// DEPLOY (Supabase Dashboard, no CLI needed):
//   1. Run calye-safe_database/supabase-login-attempts.sql in the SQL Editor.
//   2. Dashboard -> Edge Functions -> "Create a new function", name: auth-gate.
//   3. Paste this whole file as index.ts -> Deploy.
//   4. Edge Functions -> auth-gate -> Secrets -> add TURNSTILE_SECRET with the
//      Secret Key from dash.cloudflare.com -> Turnstile -> your widget.
//      (SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are
//      provided automatically — do NOT set them yourself.)
//   5. Test: curl -X POST https://<ref>.supabase.co/functions/v1/auth-gate
//      -H "apikey: <anon>" -H "Content-Type: application/json"
//      -d '{"mode":"check","token":"bad"}'  -> expect 403 human-verification.
//
// TUNING: WINDOW_MIN / MAX_EMAIL_FAILS / MAX_IP_FAILS below.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const WINDOW_MIN = 15;
const MAX_EMAIL_FAILS = 10;
const MAX_IP_FAILS = 30;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed.' }, 405);

  let payload: { mode?: string; email?: string; password?: string; token?: string } = {};
  try {
    payload = await req.json();
  } catch {
    return json({ ok: false, error: 'Bad request.' }, 400);
  }

  const token = String(payload.token || '');
  if (!token) return json({ ok: false, error: 'Human verification required.' }, 403);

  const secret = Deno.env.get('TURNSTILE_SECRET') || '';
  if (!secret) return json({ ok: false, error: 'Auth service unavailable.' }, 500);

  // 1. Verify the token with Cloudflare.
  let verdict: { success?: boolean } | null = null;
  try {
    const vr = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ secret, response: token }),
    });
    verdict = (await vr.json()) as { success?: boolean };
  } catch {
    return json({ ok: false, error: 'Verification service unreachable.' }, 502);
  }
  if (!verdict || !verdict.success) {
    return json({ ok: false, error: 'Human verification failed. Please try again.' }, 403);
  }

  const url = Deno.env.get('SUPABASE_URL') || '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
  const admin = createClient(url, serviceKey);

  const email = String(payload.email || '').toLowerCase().trim();
  const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim();

  // 2. Rate-limit check (failures inside the rolling window). Counting must
  // never lock everyone out, so errors here fail OPEN to the password check.
  const since = new Date(Date.now() - WINDOW_MIN * 60 * 1000).toISOString();
  try {
    if (email) {
      const { count } = await admin
        .from('login_attempts')
        .select('id', { count: 'exact', head: true })
        .eq('identifier', email)
        .eq('success', false)
        .gte('created_at', since);
      if ((count || 0) >= MAX_EMAIL_FAILS) {
        return json(
          { ok: false, rateLimited: true, error: 'Too many failed attempts. Try again in 15 minutes.' },
          429,
        );
      }
    }
    if (ip) {
      const { count } = await admin
        .from('login_attempts')
        .select('id', { count: 'exact', head: true })
        .eq('ip', ip)
        .eq('success', false)
        .gte('created_at', since);
      if ((count || 0) >= MAX_IP_FAILS) {
        return json(
          { ok: false, rateLimited: true, error: 'Too many failed attempts. Try again in 15 minutes.' },
          429,
        );
      }
    }
  } catch {
    /* fail open to the password check */
  }

  if (String(payload.mode || 'login') === 'check') return json({ ok: true });

  // 3. Password check, server-side, so the gate cannot be skipped.
  if (!email || !payload.password) {
    return json({ ok: false, error: 'Invalid login credentials.' }, 400);
  }
  const userClient = createClient(url, anonKey);
  const { data, error } = await userClient.auth.signInWithPassword({
    email,
    password: String(payload.password),
  });
  try {
    await admin.from('login_attempts').insert({ identifier: email, ip: ip || null, success: !error });
  } catch {
    /* logging must never break login */
  }
  if (error || !data.session) {
    // Generic on purpose: the login pages still name the faulty field
    // client-side via is_email_registered.
    return json({ ok: false, error: 'Invalid login credentials.' }, 401);
  }
  return json({ ok: true, session: data.session });
});
