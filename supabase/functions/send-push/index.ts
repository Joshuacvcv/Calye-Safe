// Calye-Safe — send-push Edge Function (true push via FCM HTTP v1)
//
// WHAT: converts a `notifications` row into phone notifications.
//   Triggered by a Database Webhook on INSERT into public.notifications.
//   Reads that user's rows in public.push_tokens, sends each an FCM message
//   (tray title/body + data payload for in-app routing), deletes tokens FCM
//   reports dead, and ignores tokens idle for 90+ days.
//
// DEPLOY (Supabase Dashboard, no CLI needed):
//   1. Run calye-safe_database/supabase-push-tokens.sql in the SQL Editor.
//   2. Dashboard -> Edge Functions -> "Create a new function", name: send-push.
//   3. Paste this whole file as index.ts -> Deploy.
//   4. Edge Functions -> send-push -> Secrets -> add FCM_SERVICE_ACCOUNT with
//      the ENTIRE service-account JSON from Firebase Console -> Project
//      settings -> Service accounts -> Generate new private key.
//      (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are automatic.)
//   5. Dashboard -> Database -> Webhooks -> Create trigger:
//        table = notifications, events = Insert,
//        URL = https://<ref>.supabase.co/functions/v1/send-push
//        (leave the service_role key default so RLS is bypassed).
//   6. Test: insert one notifications row for your own user_id, app closed —
//      the phone must buzz with that title/body.
//
// WEBHOOK PAYLOAD SHAPE (Supabase Database Webhooks):
//   { "type": "INSERT", "table": "notifications", "record": { id, user_id,
//     title, body, type, related_report_id, related_assignment_id, ... } }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { create, getNumericDate } from 'https://deno.land/x/djwt@v2.8/mod.ts';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const TOKEN_MAX_AGE_DAYS = 90;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

// --- FCM OAuth (service account -> short-lived access token, cached) --------
let cachedToken = '';
let cachedExp = 0;

async function fcmAccessToken(sa: { client_email?: string; private_key?: string }): Promise<string> {
  if (cachedToken && Date.now() < cachedExp - 60000) return cachedToken;
  const pem = String(sa.private_key || '')
    .replace(/-----.*?-----/g, '')
    .replace(/\s+/g, '');
  if (!sa.client_email || !pem) throw new Error('bad service account');
  const raw = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8',
    raw,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const jwt = await create(
    { alg: 'RS256', typ: 'JWT' },
    {
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: getNumericDate(0),
      exp: getNumericDate(60 * 60),
    },
    key,
  );
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const j = (await r.json()) as { access_token?: string };
  if (!j.access_token) throw new Error('oauth failed');
  cachedToken = j.access_token;
  cachedExp = Date.now() + 55 * 60 * 1000;
  return cachedToken;
}

// --- FCM send ---------------------------------------------------------------
async function fcmSend(
  projectId: string,
  accessToken: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<{ ok: boolean; dead: boolean }> {
  try {
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${accessToken}` },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: { priority: 'high' },
        },
      }),
    });
    if (r.ok) return { ok: true, dead: false };
    let status = '';
    try {
      const j = (await r.json()) as { error?: { status?: string } };
      status = (j.error && j.error.status) || '';
    } catch {
      /* ignore */
    }
    // UNREGISTERED / NOT_FOUND = app uninstalled or token rotated: drop it.
    return { ok: false, dead: status === 'UNREGISTERED' || status === 'NOT_FOUND' };
  } catch {
    return { ok: false, dead: false };
  }
}

// --- handler ----------------------------------------------------------------
Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ ok: false, error: 'Method not allowed.' }, 405);

  // Only the database webhook may invoke this (shared-secret bearer).
  // Without this gate, anyone could POST arbitrary title/body to ANY user.
  // The secret is a random string (NOT any Supabase key): it lives as the
  // PUSH_WEBHOOK_KEY function secret AND in Vault under push_webhook_key,
  // where the trigger reads it. Rationale: this project's auto-provided
  // SUPABASE_SERVICE_ROLE_KEY is the new sb_secret_ format while the stored
  // JWT is legacy format — comparing across formats can never match, so a
  // format-proof shared secret is used instead.
  const authHeader = (req.headers.get('authorization') || '').trim();
  const webhookKey = (Deno.env.get('PUSH_WEBHOOK_KEY') || '').trim();
  console.log('send-push: webhook key ' + (webhookKey ? ('present len=' + webhookKey.length) : 'MISSING'));
  if (!webhookKey || authHeader !== `Bearer ${webhookKey}`) {
    console.warn('send-push: rejected unauthorized call');
    return json({ ok: false, error: 'Unauthorized.' }, 401);
  }

  let payload: { type?: string; record?: Record<string, unknown> } = {};
  try {
    payload = await req.json();
  } catch {
    return json({ ok: false, error: 'Bad request.' }, 400);
  }
  if (payload.type && payload.type !== 'INSERT') {
    console.log('send-push: skipped non-INSERT type=' + payload.type);
    return json({ ok: true, skipped: true });
  }
  const rec = payload.record || {};
  const userId = String(rec.user_id || '');
  if (!userId) return json({ ok: false, error: 'No user_id.' }, 400);

  const title = String(rec.title || 'Calye-Safe');
  const body = String(rec.body || 'You have a new update.');
  const data: Record<string, string> = {
    type: String(rec.type || 'info'),
    report_id: String(rec.related_report_id || ''),
    assignment_id: String(rec.related_assignment_id || ''),
    title,
    body,
  };

  let sa: { project_id?: string; client_email?: string; private_key?: string } = {};
  try {
    sa = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT') || '{}');
  } catch {
    return json({ ok: false, error: 'Auth service unavailable.' }, 500);
  }
  if (!sa.project_id) return json({ ok: false, error: 'Auth service unavailable.' }, 500);

  const url = Deno.env.get('SUPABASE_URL') || '';
  // Server-side DB access (RLS bypass for token lookup/cleanup). The new
  // sb_secret_ format key works directly with supabase-js.
  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '');

  const cutoff = new Date(Date.now() - TOKEN_MAX_AGE_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const { data: rows, error } = await admin
    .from('push_tokens')
    .select('token')
    .eq('user_id', userId)
    .gte('updated_at', cutoff);
  if (error) return json({ ok: false, error: 'Token lookup failed.' }, 500);
  if (!rows || !rows.length) {
    console.log(`send-push: user=${userId} tokens=0 sent=0 (no devices)`);
    return json({ ok: true, sent: 0, note: 'no devices' });
  }

  let accessToken = '';
  try {
    accessToken = await fcmAccessToken(sa);
  } catch {
    return json({ ok: false, error: 'FCM auth failed.' }, 502);
  }

  let sent = 0;
  const dead: string[] = [];
  for (const row of rows as { token: string }[]) {
    const t = row.token;
    if (!t) continue;
    const res = await fcmSend(sa.project_id as string, accessToken, t, title, body, data);
    if (res.ok) sent++;
    else if (res.dead) dead.push(t);
  }
  console.log(`send-push: user=${userId} tokens=${rows.length} sent=${sent} dropped=${dead.length}`);
  if (dead.length) {
    try {
      await admin.from('push_tokens').delete().eq('user_id', userId).in('token', dead);
    } catch {
      /* cleanup must not fail the run */
    }
  }
  return json({ ok: true, sent, dropped: dead.length });
});
