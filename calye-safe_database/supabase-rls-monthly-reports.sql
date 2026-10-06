-- ============================================================================
-- Calye-Safe — RLS FOR monthly_reports (companion to supabase-rls-production.sql)
--
-- WHY:
--   supabase-rls-production.sql locks 13 tables but never touches
--   monthly_reports, so the analytics snapshot table would stay UNRESTRICTED
--   (anon key reads everything) after the production migration.
--
-- DESIGN:
--   * Reads: staff/admin only (admin analytics console, signed-in session).
--   * Writes: NO api policy at all — rows are written only by the pg_cron job
--     and the SECURITY DEFINER analytics functions, which bypass RLS as the
--     table owner. Nobody can write through PostgREST, by design.
--   * Self-contained: defines its own staff helper (same pattern as the
--     production file). Safe to re-run. Run BEFORE or AFTER
--     supabase-rls-production.sql — order does not matter.
--
-- RUN IN THE SUPABASE SQL EDITOR.
-- ============================================================================

alter table public.monthly_reports enable row level security;

create or replace function public.auth_is_staff()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role in ('staff', 'admin')
  );
$$;

drop policy if exists "monthly_reports_staff_select" on monthly_reports;
create policy "monthly_reports_staff_select"
  on monthly_reports for select using (auth_is_staff());

-- No INSERT / UPDATE / DELETE policies: direct API writes are denied entirely.
-- The monthly pg_cron job ('calye-monthly-report') and SECURITY DEFINER
-- functions bypass RLS as owner, so automation keeps working.

-- ============================================================================
-- VERIFY AFTER RUNNING:
--   select tablename, rowsecurity from pg_tables
--   where schemaname = 'public' and tablename = 'monthly_reports';
-- Must show rowsecurity = true.
-- ============================================================================
