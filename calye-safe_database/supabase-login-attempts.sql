-- ============================================================================
-- Calye-Safe — LOGIN ATTEMPT LOG (powers the auth-gate rate limiter)
--
-- WHY:
--   The auth-gate Edge Function verifies the Turnstile token server-side,
--   then counts recent FAILED password attempts per email (10 / 15 min) and
--   per IP (30 / 15 min) before it even tries the password. This table is
--   that counter. Successes are logged too (one row per attempt) so a
--   successful login clears the caller's failure streak implicitly — only
--   failures inside the rolling window count.
--
-- PRIVACY:
--   One row per attempt (identifier + ip + timestamp). No passwords, ever.
--   Prune monthly: delete from public.login_attempts
--                  where created_at < now() - interval '30 days';
--
-- SAFETY:
--   * RLS enabled with NO policies: the API can never read or write it.
--     The Edge Function uses the service_role key, which bypasses RLS.
--   * Safe to re-run.
--
-- RUN IN THE SUPABASE SQL EDITOR (before deploying the auth-gate function).
-- ============================================================================

create table if not exists public.login_attempts (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  identifier text not null default '',
  ip         text,
  success    boolean not null default false
);

alter table public.login_attempts enable row level security;

-- No GRANTs / policies on purpose: anon + authenticated get nothing.
-- service_role (Edge Function) bypasses RLS.

create index if not exists login_attempts_identifier_time
  on public.login_attempts (identifier, created_at desc)
  where success = false;

create index if not exists login_attempts_ip_time
  on public.login_attempts (ip, created_at desc)
  where success = false;

-- ============================================================================
-- VERIFY AFTER RUNNING:
--   select tablename, rowsecurity from pg_tables
--   where schemaname = 'public' and tablename = 'login_attempts';
-- Must show rowsecurity = true.
-- ============================================================================
