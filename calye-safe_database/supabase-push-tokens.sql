-- ============================================================================
-- Calye-Safe — PUSH TOKENS (device registry for true push notifications)
--
-- WHY:
--   In-app notifications die with the app. The send-push Edge Function reads
--   this table to find where to deliver: notifications.user_id -> all tokens
--   of that user -> FCM HTTP v1. One user may own several rows (2 phones).
--
-- PRIVACY:
--   FCM tokens are routing addresses, not content. Owner-only API access;
--   the service_role sender bypasses RLS. Tokens refresh on every app start
--   (updated_at = liveness); the sender ignores rows older than 90 days, and
--   delete-on-logout + FCM-invalid cleanup keep the table small. No prune
--   job needed, but one is harmless:
--     delete from public.push_tokens where updated_at < now() - interval '90 days';
--
-- SAFETY:
--   * Composite primary key (user_id, token): re-registering the same token
--     is an upsert, never a duplicate row.
--   * RLS enabled with owner-only policies (insert/select/update/delete).
--     The client upserts with onConflict=user_id,token, which needs both the
--     insert and the update policy below.
--   * Safe to re-run.
--
-- RUN IN THE SUPABASE SQL EDITOR (before deploying send-push).
-- ============================================================================

create table if not exists public.push_tokens (
  user_id    uuid not null,
  token      text not null,
  platform   text not null default 'android',
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

alter table public.push_tokens enable row level security;

drop policy if exists "push_tokens_owner_insert" on push_tokens;
create policy "push_tokens_owner_insert"
  on push_tokens for insert with check (auth.uid() = user_id);

drop policy if exists "push_tokens_owner_select" on push_tokens;
create policy "push_tokens_owner_select"
  on push_tokens for select using (auth.uid() = user_id);

drop policy if exists "push_tokens_owner_update" on push_tokens;
create policy "push_tokens_owner_update"
  on push_tokens for update using (auth.uid() = user_id);

drop policy if exists "push_tokens_owner_delete" on push_tokens;
create policy "push_tokens_owner_delete"
  on push_tokens for delete using (auth.uid() = user_id);

create index if not exists push_tokens_user_time
  on public.push_tokens (user_id, updated_at desc);

-- ============================================================================
-- VERIFY AFTER RUNNING:
--   select tablename, rowsecurity from pg_tables
--   where schemaname = 'public' and tablename = 'push_tokens';
-- Must show rowsecurity = true.
-- ============================================================================
