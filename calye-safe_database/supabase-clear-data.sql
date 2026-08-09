-- ============================================================================
-- Calye-Safe — CLEAR ALL APP DATA
-- ----------------------------------------------------------------------------
-- Wipes every row the apps create, in foreign-key-safe order, so you can
-- re-discover back to a blank slate. Auth accounts (auth.users) are kept so
-- sign-ins still work; their profiles in `profiles` are also kept unless you
-- uncomment the last block.
--
-- Run this whole script in the Supabase SQL editor.
-- ============================================================================

-- Child rows first (respects FK / cascades so nothing orphan fails).
delete from notifications;
delete from resolved_history;
delete from assignment_timeline;
delete from report_timeline;
delete from report_media;
delete from verification_requests;
delete from announcements;
delete from map_incidents;
delete from assignments;
delete from reports;
delete from hotlines;
delete from responders;

-- Optional: also wipe resident/responder identity + monthly analytics cache.
-- delete from monthly_reports;
-- delete from profiles;

-- Postgres identity columns use gen_random_uuid()/bigserial-style defaults,
-- so there's nothing to reset; but keep vivacious-fresh DBs tidy:
-- alter table reports            alter column id set default gen_random_uuid();
-- (no-op, already default.)

-- Verify it's empty.
select 'reports',            count(*) from reports
union all select 'assignments',      count(*) from assignments
union all select 'report_timeline',  count(*) from report_timeline
union all select 'announcements',    count(*) from announcements
union all select 'map_incidents',    count(*) from map_incidents;