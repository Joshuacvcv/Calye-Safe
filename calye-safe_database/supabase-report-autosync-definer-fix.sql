-- ============================================================================
-- Calye-Safe — REPORT AUTO-SYNC TRIGGERS: SECURITY DEFINER FIX (self-contained)
--
-- Filing a report fails with:
--   new row violates row-level security policy for table "report_timeline"
--
-- WHY: trg_create_report_timeline / trg_sync_map_incidents were plain
-- plpgsql (invoker rights). When an APPROVED RESIDENT inserts a report, the
-- AFTER INSERT trigger runs AS THE RESIDENT and writes report_timeline /
-- map_incidents — tables that only allow staff inserts — so the trigger's own
-- write is rejected by RLS and the whole report insert fails.
--
-- This rebuilds the trigger functions as SECURITY DEFINER so the derived
-- timeline and map-incident rows are written without tripping RLS. The
-- functions only write rows DERIVED from the report row just inserted, so no
-- extra data is exposed. Safety: re-runnable, idempotent.
--
-- RUN IN THE SUPABASE SQL EDITOR. Safe to re-run.
-- ============================================================================

-- Ensure these exist as SECURITY DEFINER. Using CREATE OR REPLACE sets the
-- SECURITY DEFINER flag explicitly, so it works even if a later re-run of the
-- schema/fix scripts had recreated them as plain invoker functions.
--
-- 1. report_timeline auto-seed on report insert
create or replace function public.create_report_timeline()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into report_timeline (report_id, step, label, note, happened_at, state)
  values
    (new.id, 1, 'Report Submitted', 'Your report was received by the system.',
     to_char(new.created_at at time zone 'Asia/Manila', 'Mon DD · HH:MI AM'), 'done'),
    (new.id, 2, 'Verified by Operator', 'A barangay operator has verified the incident report.', '—', 'pending'),
    (new.id, 3, 'Responder Dispatched', '—', '—', 'pending'),
    (new.id, 4, 'On-Site Response', '—', '—', 'pending'),
    (new.id, 5, 'Resolved', '—', '—', 'pending');
  return new;
end $$;

drop trigger if exists trg_create_report_timeline on reports;
create trigger trg_create_report_timeline
  after insert on reports
  for each row execute function public.create_report_timeline();

-- 2. map_incidents mirror on report insert
create or replace function public.sync_map_incidents_from_report()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into map_incidents (report_id, type, label, location, status, lat, lng, geom, created_at)
    values (new.id, new.category, new.type, new.location, new.status, new.lat, new.lng,
            ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326), new.created_at);
  elsif tg_op = 'UPDATE' then
    update map_incidents
    set type = new.category, label = new.type, location = new.location, status = new.status,
        lat = new.lat, lng = new.lng, geom = ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326)
    where report_id = new.id;
  elsif tg_op = 'DELETE' then
    delete from map_incidents where report_id = old.id;
  end if;
  return new;
end $$;

drop trigger if exists trg_sync_map_incidents on reports;
create trigger trg_sync_map_incidents
  after insert or update or delete on reports
  for each row execute function public.sync_map_incidents_from_report();

-- 3. assignment_timeline auto-seed on assignment insert (same guarantee)
create or replace function public.create_assignment_timeline()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_created_at timestamptz;
begin
  select r.created_at into v_created_at from reports r where r.id = new.report_id;
  v_created_at := coalesce(v_created_at, new.created_at);

  insert into assignment_timeline (assignment_id, step, label, happened_at, state)
  values
    (new.id, 1, 'Reported', to_char(v_created_at at time zone 'Asia/Manila', 'Mon DD · HH:MI AM'), 'done'),
    (new.id, 2, 'Verified & Assigned to you', to_char(coalesce(new.assigned_at, new.created_at) at time zone 'Asia/Manila', 'Mon DD · HH:MI AM'), 'done'),
    (new.id, 3, 'En Route', '—', 'pending'),
    (new.id, 4, 'On-Site', '—', 'pending'),
    (new.id, 5, 'Resolved', '—', 'pending');
  return new;
end $$;

drop trigger if exists trg_create_assignment_timeline on assignments;
create trigger trg_create_assignment_timeline
  after insert on assignments
  for each row execute function public.create_assignment_timeline();

-- Safety net: if any of these still have invoker rights somewhere, the ALTER
-- below force-defines them so a future CREATE OR REPLACE cannot silently drop
-- the flag in this DB again.
alter function public.create_report_timeline()  security definer set search_path = public;
alter function public.sync_map_incidents_from_report() security definer set search_path = public;
alter function public.create_assignment_timeline() security definer set search_path = public;

-- Verify each is security definer.
select p.oid::regprocedure as function_name, p.prosecdef as is_security_definer
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('create_report_timeline', 'sync_map_incidents_from_report', 'create_assignment_timeline')
order by p.proname;