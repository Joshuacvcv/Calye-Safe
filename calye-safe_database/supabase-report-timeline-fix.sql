-- ============================================================================
-- FIX: Rebuild the resident's report_timeline from REAL state
-- ----------------------------------------------------------------------------
-- Problem: report_timeline rows were seeded with fabricated happened_at times
-- and active/done states (supabase-seed.sql), so the resident app showed
-- "Reported at May 16" plus timestamps on steps that were never performed.
--
-- This script:
--   1. Ensures the auto-sync trigger exists (canonical 5-step rows on insert).
--   2. Wipes the fabricated rows and rebuilds report_timeline so each step is
--      'done' ONLY when the real report/assignment state says it happened.
-- Run this whole script in the Supabase SQL editor AFTER you've dispatched is
-- fine for any state (it recomputes from data).
-- ============================================================================

-- 1. Ensure the report_timeline trigger is installed (idempotent).
-- SECURITY DEFINER so the resident's own report insert does not trip RLS
-- when this trigger writes the derived timeline rows.
create or replace function create_report_timeline()
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
  for each row execute function create_report_timeline();

-- 2. Remove old, possibly-fabricated rows.
delete from report_timeline;

-- 3. Rebuild step 1: every report was submitted, stamped with its real time.
insert into report_timeline (report_id, step, label, note, happened_at, state)
select r.id, 1, 'Report Submitted', 'Your report was received by the system.',
       to_char(r.created_at at time zone 'Asia/Manila', 'Mon DD · HH:MI AM'), 'done'
from reports r;

-- 4. Step 2 (Verified by Operator): done only when a responder was assigned,
--    timestamped at the assignment/dispatch moment.
insert into report_timeline (report_id, step, label, note, happened_at, state)
select a.report_id, 2, 'Verified by Operator',
       'A barangay operator has verified the incident report.',
       to_char(coalesce(a.assigned_at, a.created_at) at time zone 'Asia/Manila', 'Mon DD · HH:MI AM'), 'done'
from assignments a
where a.report_id is not null
on conflict (report_id, step) do nothing;

-- 5. Step 3 (Responder Dispatched): done when the responder actually en-route
--    (assignment moved past 'assigned').
insert into report_timeline (report_id, step, label, note, happened_at, state)
select a.report_id, 3, 'Responder Dispatched',
       'Responder unit is en route to your location.',
       to_char(coalesce(a.assigned_at, a.created_at) at time zone 'Asia/Manila', 'Mon DD · HH:MI AM'), 'done'
from assignments a
where a.report_id is not null
  and a.status in ('en_route', 'on_site', 'resolved')
on conflict (report_id, step) do nothing;

-- 6. Step 4 (On-Site Response): done when a responder reached the site.
insert into report_timeline (report_id, step, label, note, happened_at, state)
select a.report_id, 4, 'On-Site Response',
       'Responder is on site working on the incident.',
       to_char(coalesce(a.resolved_at, a.assigned_at, a.created_at) at time zone 'Asia/Manila', 'Mon DD · HH:MI AM'), 'done'
from assignments a
where a.report_id is not null
  and a.status in ('on_site', 'resolved')
on conflict (report_id, step) do nothing;

-- 7. Step 5 (Resolved): done only when the report is actually resolved.
insert into report_timeline (report_id, step, label, note, happened_at, state)
select r.id, 5, 'Resolved',
       'Report has been resolved.',
       to_char(coalesce(a.resolved_at, r.created_at) at time zone 'Asia/Manila', 'Mon DD · HH:MI AM'), 'done'
from reports r
left join assignments a on a.report_id = r.id
  and a.status = 'resolved'
where r.status = 'resolved'
on conflict (report_id, step) do nothing;

-- 8. Leftover reports without any report_timeline row yet? Give them step 1
--    (assigned in step 3 above) — done — plus the rest pending.
insert into report_timeline (report_id, step, label, note, happened_at, state)
select r.id, s.step, s.label, s.note, '—', 'pending'
from reports r
cross join (values
  (2, 'Verified by Operator', 'A barangay operator has verified the incident report.'),
  (3, 'Responder Dispatched', ''),
  (4, 'On-Site Response', ''),
  (5, 'Resolved', '')
) as s(step, label, note)
where not exists (select 1 from report_timeline t where t.report_id = r.id and t.step = s.step);

-- 9. Doctor pending rows across all reports so nothing shows a time before
--    a step was actually done.
update report_timeline
set state = 'pending'
where state is null;

-- Verification: view real timeline for the most recent reports.
select r.report_no, t.step, t.label, t.happened_at, t.state
from reports r
join report_timeline t on t.report_id = r.id
order by r.created_at desc, t.step asc
limit 40;