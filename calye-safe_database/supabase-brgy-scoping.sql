-- ============================================================================
-- Calye-Safe — PER-BARANGAY SCOPING FOR THE ADMIN DASHBOARD
--
--   The single `admin` account keeps the CITY-WIDE view (all of Santa Rosa).
--   Every `staff` account is scoped to ONE barangay: its map, its reports,
--   its analytics. Scope comes from profiles.barangay (the value picked at
--   registration).
--
--   WHAT THIS FILE DOES
--     1. Adds reports.barangay + map_incidents.barangay (+ indexes)
--     2. Backfills both from profiles.barangay / reports.barangay
--     3. Rebuilds sync_map_incidents_from_report() so every report edit
--        mirrors barangay onto its public map pin (SECURITY DEFINER, same
--        shape as supabase-report-autosync-definer-fix.sql — whichever of
--        the two is live, this one wins because it runs last)
--     4. Adds auth_brgy():  NULL  -> city-wide (role admin OR responder)
--                          text  -> that staff member's barangay
--     5. Rewrites the staff RLS policies so `staff` rows are limited to
--        their own barangay while `admin` still sees everything
--
--   WHY RESPONDERS STAY CITY-WIDE: the field responder app
--   (calye-safe-responders.html) is a mobile unit that answers calls all
--   over the city — scoping it would break dispatch. Only the dashboard's
--   `staff` role (the barangay admins) is limited.
--
--   RUN IN THE SUPABASE SQL EDITOR. Idempotent — safe to re-run.
--
--   DEPENDENCY: run AFTER supabase-rls-production.sql.
-- ============================================================================


-- ── 1. COLUMNS ──────────────────────────────────────────────────────────────
alter table public.reports       add column if not exists barangay text;
alter table public.map_incidents add column if not exists barangay text;

create index if not exists idx_reports_barangay        on public.reports (barangay);
create index if not exists idx_map_incidents_barangay  on public.map_incidents (barangay);


-- ── 2. BACKFILL ─────────────────────────────────────────────────────────────
-- Reports inherit the reporter's registered barangay. New reports are stamped
-- by the community app at filing time (reverse-geocoded pin, falling back to
-- the reporter's own barangay), so this only touches pre-existing rows.
update public.reports r
   set barangay = coalesce(nullif(p.barangay, ''), 'Barangay Calye')
  from public.profiles p
 where p.id = r.reporter_id
   and r.barangay is null;

-- Rows with no reporter (seed/demo data) fall back to the legacy default so
-- the coalesce() used inside every policy below is never NULL.
update public.reports
   set barangay = 'Barangay Calye'
 where barangay is null;

update public.map_incidents m
   set barangay = r.barangay
  from public.reports r
 where r.id = m.report_id
   and m.barangay is null;


-- ── 3. MAP-PIN MIRROR TRIGGER (rebuild, with barangay) ──────────────────────
-- SECURITY DEFINER: an approved resident's insert must be able to write the
-- derived map_incidents row without tripping RLS (see
-- supabase-report-autosync-definer-fix.sql for the original reasoning).
create or replace function public.sync_map_incidents_from_report()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into map_incidents (report_id, type, label, location, status, lat, lng, geom, created_at, barangay)
    values (new.id, new.category, new.type, new.location, new.status, new.lat, new.lng,
            ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326), new.created_at, new.barangay);
  elsif tg_op = 'UPDATE' then
    update map_incidents
       set type = new.category, label = new.type, location = new.location, status = new.status,
           lat = new.lat, lng = new.lng, geom = ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326),
           barangay = new.barangay
     where report_id = new.id;
  elsif tg_op = 'DELETE' then
    delete from map_incidents where report_id = old.id;
  end if;
  return new;
end $$;

drop trigger if exists trg_sync_map_incidents on public.reports;
create trigger trg_sync_map_incidents
  after insert or update or delete on public.reports
  for each row execute function public.sync_map_incidents_from_report();


-- ── 4. SCOPE HELPER ─────────────────────────────────────────────────────────
-- Returns the barangay the CALLER is confined to, or NULL for "no limit".
--   role = admin      -> NULL  (the city-wide account: sees all of Santa Rosa)
--   role = responder  -> NULL  (field units are dispatched city-wide)
--   role = staff      -> profiles.barangay (the barangay admin)
-- SECURITY DEFINER + empty search_path, exactly like auth_is_staff(), so a
-- policy can read `profiles` without recursing back into profiles' own RLS.
create or replace function public.auth_brgy()
returns text
language sql stable security definer set search_path = ''
as $$
  select case
           when (select p.role::text from public.profiles p where p.id = auth.uid())
                in ('admin', 'responder')
             then null::text
           else coalesce(
             nullif((select p.barangay from public.profiles p where p.id = auth.uid()), ''),
             'Barangay Calye'
           )
         end;
$$;

revoke execute on function public.auth_brgy() from public;
grant  execute on function public.auth_brgy() to authenticated;


-- ── 5. REPORTS ──────────────────────────────────────────────────────────────
-- coalesce(barangay,'Barangay Calye') mirrors the backfill above: a row that
-- was never stamped still lands in the legacy scope instead of vanishing.
drop policy if exists "reports_staff_insert" on public.reports;
create policy "reports_staff_insert" on public.reports for insert with check (
  auth_is_staff() and auth_is_approved()
  and (auth_brgy() is null or coalesce(barangay, 'Barangay Calye') = auth_brgy())
);

drop policy if exists "reports_staff_select" on public.reports;
create policy "reports_staff_select" on public.reports for select using (
  auth_is_responder()
  and (auth_brgy() is null or coalesce(barangay, 'Barangay Calye') = auth_brgy())
);

-- No separate WITH CHECK: Postgres applies the USING expression to new rows
-- too, so a scoped staff member can neither read nor move another barangay's
-- report.
drop policy if exists "reports_staff_update" on public.reports;
create policy "reports_staff_update" on public.reports for update using (
  auth_is_responder() and auth_is_approved()
  and (auth_brgy() is null or coalesce(barangay, 'Barangay Calye') = auth_brgy())
);


-- ── 6. REPORT TIMELINE (per-report activity log) ────────────────────────────
-- The resident always reads their own report's timeline; the staff branch is
-- now confined to the caller's barangay.
drop policy if exists "timeline_owner_select" on public.report_timeline;
create policy "timeline_owner_select" on public.report_timeline for select using (
  exists (select 1 from public.reports r where r.id = report_id and r.reporter_id = auth.uid())
  or (
    auth_is_responder()
    and (auth_brgy() is null or exists (
      select 1 from public.reports r
       where r.id = report_timeline.report_id
         and coalesce(r.barangay, 'Barangay Calye') = auth_brgy()
    ))
  )
);


-- ── 7. REPORT MEDIA (evidence photos) ───────────────────────────────────────
-- The dashboard pulls report_media with no filter, so this is what actually
-- stops a scoped staff account from reading another barangay's evidence URLs.
drop policy if exists "media_owner_select" on public.report_media;
create policy "media_owner_select" on public.report_media for select using (
  exists (select 1 from public.reports r where r.id = report_id and r.reporter_id = auth.uid())
  or (
    auth_is_responder()
    and (auth_brgy() is null or exists (
      select 1 from public.reports r
       where r.id = report_media.report_id
         and coalesce(r.barangay, 'Barangay Calye') = auth_brgy()
    ))
  )
);


-- ── 8. ASSIGNMENTS ──────────────────────────────────────────────────────────
-- assignments has no barangay column of its own — scope is derived from the
-- report it points at.
drop policy if exists "assignments_staff_select" on public.assignments;
create policy "assignments_staff_select" on public.assignments for select using (
  auth_is_responder()
  and (auth_brgy() is null or exists (
    select 1 from public.reports r
     where r.id = assignments.report_id
       and coalesce(r.barangay, 'Barangay Calye') = auth_brgy()
  ))
);

drop policy if exists "assignments_staff_insert" on public.assignments;
create policy "assignments_staff_insert" on public.assignments for insert with check (
  auth_is_staff() and auth_is_approved()
  and (auth_brgy() is null or exists (
    select 1 from public.reports r
     where r.id = assignments.report_id
       and coalesce(r.barangay, 'Barangay Calye') = auth_brgy()
  ))
);

drop policy if exists "assignments_staff_update" on public.assignments;
create policy "assignments_staff_update" on public.assignments for update using (
  auth_is_responder() and auth_is_approved()
  and (auth_brgy() is null or exists (
    select 1 from public.reports r
     where r.id = assignments.report_id
       and coalesce(r.barangay, 'Barangay Calye') = auth_brgy()
  ))
);


-- ============================================================================
-- DELIBERATELY NOT SCOPED
--
--   map_incidents  SELECT stays `using (true)`. The RESIDENT community map
--                  shows every incident in the city by design, and a pin
--                  carries no PII (type / label / location / status / lat /
--                  lng only). The dashboard filters pins to the signed-in
--                  staff member's barangay in the UI instead.
--
--   responders,
--   profiles,
--   announcements   operational directories, not incident data — left as-is.
--
--   fn_incident_summary() / fn_monthly_summary() /
--   fn_responder_monthly_performance()
--                  SECURITY DEFINER, so they bypass RLS and would return
--                  city-wide numbers to a scoped account. The dashboard
--                  skips these RPCs whenever a scope is active and
--                  aggregates the already-filtered rows client-side
--                  (computeAnalyticsSummary / computeResponderPerformancePage).
-- ============================================================================


-- ── VERIFY (SQL Editor) ─────────────────────────────────────────────────────
-- Should return 3 rows (insert / select / update):
--
--   select p.policename from pg_policies p
--    where p.schemaname = 'public' and p.tablename = 'reports'
--      and p.policename like 'reports_staff%';
--
-- Smoke test of the helper (sign in as each account first):
--   select public.auth_brgy();   -- admin -> null, staff -> 'Balibago', …
--
-- And give each barangay admin its scope (one row per account):
--   update public.profiles set barangay = 'Balibago'
--    where email = 'brgy.balibago@calye.ph' and role = 'staff';
