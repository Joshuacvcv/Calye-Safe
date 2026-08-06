-- ============================================================================
-- Calye-Safe — PRODUCTION RLS MIGRATION (Gap 8)
--
-- Reverse supabase-demo-access.sql and harden every table so row-level
-- security is enforced again with the policies that already exist in
-- supabase-schema.sql, supabase-verification.sql, supabase-fixes.sql and
-- supabase-notifications-rls-fix.sql.
--
-- WHAT THIS DOES:
--   1. Re-enables RLS on every table the demo migration disabled.
--   2. Re-asserts all per-role policies (idempotent: safe to re-run).
--   3. Leaves the public-by-design surfaces open to the anon key ONLY:
--        - hotlines        (public emergency numbers)
--        - map_incidents   (public map pins)
--        - announcements   (rows with pushed = true)
--      Everything personal (profiles, reports, media, responders,
--      assignments, history, verification, notifications) now REQUIRES a
--      real signed-in session. The anon key returns 0 rows for those.
--
-- RUN IN THE SUPABASE SQL EDITOR when you are ready to enforce security AND
-- the apps are wired to sign in with real accounts (see supabase-rls-runbook).
-- Safe to re-run.
-- ============================================================================

-- ── 1. RE-ENABLE ROW LEVEL SECURITY ON EVERY TABLE ---------------------------
-- (The demo migration disabled these. Re-enable is idempotent.)
alter table public.profiles               enable row level security;
alter table public.reports                enable row level security;
alter table public.report_timeline        enable row level security;
alter table public.report_media           enable row level security;
alter table public.responders             enable row level security;
alter table public.assignments            enable row level security;
alter table public.assignment_timeline    enable row level security;
alter table public.resolved_history       enable row level security;
alter table public.announcements          enable row level security;
alter table public.hotlines               enable row level security;
alter table public.map_incidents          enable row level security;
alter table public.verification_requests  enable row level security;
alter table public.notifications          enable row level security;


-- ── 2. ROLE HELPERS (idempotent — kept here so this file is self-contained) --
-- SECURITY DEFINER: these read `profiles`, and without definer rights a policy
-- referencing them re-triggers RLS on profiles from inside the profiles policy
-- → infinite recursion (ERROR 54001 stack depth / 57014 timeout). Definer runs
-- the internal SELECT as the owner, bypassing RLS on that subquery.
-- `set search_path = ''` prevents search-path hijacking; all refs are qualified.
create or replace function auth_is_staff()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role in ('staff', 'admin')
  );
$$;

create or replace function auth_is_responder()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role in ('responder', 'staff', 'admin')
  );
$$;

-- Approved = the admin Verify-Users queue set verification_status = 'approved'.
-- Unapproved ('pending') accounts can manage their own profile + verification
-- request (that is how they GET approved) but cannot touch system data.
create or replace function auth_is_approved()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.verification_status = 'approved'
  );
$$;


-- ── 3. PROFILES --------------------------------------------------------------
drop policy if exists "profiles_self_select" on profiles;
create policy "profiles_self_select"   on profiles for select using (auth.uid() = id);
drop policy if exists "profiles_self_insert" on profiles;
create policy "profiles_self_insert"   on profiles for insert with check (auth.uid() = id);

-- SELF UPDATE: users may edit their own row BUT the `with check` prevents
-- privilege escalation. `role` can never change. `verification_status` may
-- only stay the same OR downgrade to 'pending' (rejected -> resubmit); a user
-- can never self-approve (-> approved).
drop policy if exists "profiles_self_update" on profiles;
create policy "profiles_self_update" on profiles for update
  using (auth.uid() = id)
  with check (
    auth.uid() = id
    and role = (select role from profiles where id = auth.uid())
    and (
      verification_status = (select verification_status from profiles where id = auth.uid())
      or verification_status = 'pending'
    )
  );

drop policy if exists "profiles_staff_select" on profiles;
create policy "profiles_staff_select"  on profiles for select using (auth_is_staff());

-- STAFF UPDATE: lets staff/admin approve, reject, or change roles of other
-- users (Verify-Users queue). No `with check` -> defaults to `auth_is_staff()`
-- so any new row written through this policy must also be an action by staff.
drop policy if exists "profiles_staff_update" on profiles;
create policy "profiles_staff_update" on profiles for update using (auth_is_staff());

-- ── 4. REPORTS ---------------------------------------------------------------
drop policy if exists "reports_resident_insert" on reports;
create policy "reports_resident_insert" on reports for insert with check (
  auth.uid() = reporter_id and auth_is_approved()
);
drop policy if exists "reports_staff_insert" on reports;
create policy "reports_staff_insert" on reports for insert with check (
  auth_is_staff() and auth_is_approved()
);
drop policy if exists "reports_owner_select" on reports;
create policy "reports_owner_select"    on reports for select using (auth.uid() = reporter_id);
drop policy if exists "reports_staff_select" on reports;
create policy "reports_staff_select"    on reports for select using (auth_is_responder());
drop policy if exists "reports_staff_update" on reports;
create policy "reports_staff_update"    on reports for update using (
  auth_is_responder() and auth_is_approved()
);

-- ── 5. REPORT TIMELINE -------------------------------------------------------
drop policy if exists "timeline_owner_select" on report_timeline;
create policy "timeline_owner_select"   on report_timeline for select using (
  exists (select 1 from reports r where r.id = report_id and r.reporter_id = auth.uid())
  or auth_is_responder()
);
drop policy if exists "timeline_staff_insert" on report_timeline;
create policy "timeline_staff_insert"   on report_timeline for insert with check (
  auth_is_responder() and auth_is_approved()
);

-- ── 6. REPORT MEDIA ----------------------------------------------------------
drop policy if exists "media_owner_select" on report_media;
create policy "media_owner_select"       on report_media for select using (
  exists (select 1 from reports r where r.id = report_id and r.reporter_id = auth.uid())
  or auth_is_responder()
);
drop policy if exists "media_owner_insert" on report_media;
create policy "media_owner_insert"       on report_media for insert with check (
  auth_is_approved()
  and auth.uid() = (select reporter_id from reports where id = report_id)
);

-- ── 7. RESPONDERS ------------------------------------------------------------
drop policy if exists "responders_select" on responders;
create policy "responders_select"        on responders for select using (auth_is_responder());
drop policy if exists "responders_update" on responders;
create policy "responders_update"        on responders for update using (auth_is_staff());

-- ── 8. ASSIGNMENTS -----------------------------------------------------------
drop policy if exists "assignments_staff_select" on assignments;
create policy "assignments_staff_select" on assignments for select using (auth_is_responder());
drop policy if exists "assignments_staff_insert" on assignments;
create policy "assignments_staff_insert" on assignments for insert with check (
  auth_is_staff() and auth_is_approved()
);
drop policy if exists "assignments_staff_update" on assignments;
create policy "assignments_staff_update" on assignments for update using (
  auth_is_responder() and auth_is_approved()
);

-- ── 9. ASSIGNMENT TIMELINE ---------------------------------------------------
drop policy if exists "at_timeline_select" on assignment_timeline;
create policy "at_timeline_select"       on assignment_timeline for select using (auth_is_responder());
drop policy if exists "at_timeline_insert" on assignment_timeline;
create policy "at_timeline_insert"       on assignment_timeline for insert with check (
  auth_is_responder() and auth_is_approved()
);

-- ── 10. RESOLVED HISTORY -----------------------------------------------------
drop policy if exists "history_responder_select" on resolved_history;
create policy "history_responder_select" on resolved_history for select using (auth_is_responder());

-- ── 11. ANNOUNCEMENTS --------------------------------------------------------
drop policy if exists "announcements_public_select" on announcements;
create policy "announcements_public_select" on announcements for select using (pushed = true or auth_is_staff());
drop policy if exists "announcements_staff_insert" on announcements;
create policy "announcements_staff_insert" on announcements for insert with check (auth_is_staff());
drop policy if exists "announcements_staff_update" on announcements;
create policy "announcements_staff_update" on announcements for update using (auth_is_staff());
drop policy if exists "announcements_staff_delete" on announcements;
create policy "announcements_staff_delete" on announcements for delete using (auth_is_staff());

-- ── 12. HOTLINES (public by design) ------------------------------------------
drop policy if exists "hotlines_public_select" on hotlines;
create policy "hotlines_public_select"   on hotlines for select using (true);
drop policy if exists "hotlines_staff_insert" on hotlines;
create policy "hotlines_staff_insert"    on hotlines for insert with check (auth_is_staff());

-- ── 13. MAP INCIDENTS (public pins by design) -------------------------------
drop policy if exists "map_incidents_public_select" on map_incidents;
create policy "map_incidents_public_select" on map_incidents for select using (true);
drop policy if exists "map_incidents_staff_insert" on map_incidents;
create policy "map_incidents_staff_insert" on map_incidents for insert with check (auth_is_staff());
drop policy if exists "map_incidents_staff_update" on map_incidents;
create policy "map_incidents_staff_update" on map_incidents for update using (auth_is_staff());

-- ── 14. VERIFICATION REQUESTS -----------------------------------------------
drop policy if exists "verif_req_owner_select" on verification_requests;
create policy "verif_req_owner_select"   on verification_requests for select using (auth.uid() = user_id);
drop policy if exists "verif_req_owner_insert" on verification_requests;
create policy "verif_req_owner_insert"   on verification_requests for insert with check (auth.uid() = user_id);
drop policy if exists "verif_req_staff_select" on verification_requests;
create policy "verif_req_staff_select"   on verification_requests for select using (auth_is_staff());
drop policy if exists "verif_req_staff_update" on verification_requests;
create policy "verif_req_staff_update"   on verification_requests for update using (auth_is_staff());

-- ── 15. NOTIFICATIONS -------------------------------------------------------
-- Inserts are always done by the SECURITY DEFINER trigger functions
-- (notify_report_status_change / notify_new_assignment) so users only need
-- SELECT on their own rows and UPDATE to mark read.
drop policy if exists "notifications_self_select" on notifications;
create policy "notifications_self_select" on notifications for select using (auth.uid() = user_id);
drop policy if exists "notifications_self_update" on notifications;
create policy "notifications_self_update" on notifications for update using (auth.uid() = user_id);
drop policy if exists "notifications_staff_insert" on notifications;
create policy "notifications_staff_insert" on notifications for insert with check (
  auth_is_staff()
);

-- ── 16. ANALYTICS RPCs — REMOVE Anon, require a real session ----------------
-- These functions are SECURITY DEFINER (they bypass RLS) and were granted to
-- `anon`, so anyone with the anon key could pull aggregate incident stats +
-- hotspots. Restrict them to signed-in users.
revoke execute on function fn_incident_summary(timestamptz, timestamptz) from anon;
revoke execute on function fn_incident_density(timestamptz, timestamptz) from anon;
revoke execute on function fn_monthly_summary(int, int) from anon;
grant execute on function fn_incident_summary(timestamptz, timestamptz) to authenticated;
grant execute on function fn_incident_density(timestamptz, timestamptz) to authenticated;
grant execute on function fn_monthly_summary(int, int) to authenticated;

-- ============================================================================
-- VERIFY AFTER RUNNING (SQL Editor):
--   select tablename, rowsecurity
--   from pg_tables
--   where schemaname = 'public' and tablename in
--     ('profiles','reports','report_timeline','report_media','responders',
--      'assignments','assignment_timeline','resolved_history','announcements',
--      'hotlines','map_incidents','verification_requests','notifications')
--   order by tablename;
-- Every row should show rowsecurity = true.
-- ============================================================================