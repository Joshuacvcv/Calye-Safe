-- ============================================================================
-- Calye-Safe — REPORT SUBMISSION RLS FIX
--
-- Filing a report did more than insert into `reports`: the community app also
-- writes the initial 5-step status timeline and the public map incident. Those
-- two tables only had STAFF insert policies, so an approved resident's report
-- was rejected with:
--     new row violates row-level security policy for table "report_timeline"
--     new row violates row-level security policy for table "map_incidents"
--
-- FIX: allow an approved resident to insert the FIRST timeline row and the
-- map incident ONLY for their OWN report (same pattern as media_owner_insert).
-- Staff/responder writes keep working via the existing policies.
--
-- RUN IN THE SUPABASE SQL EDITOR. Safe to re-run.
-- ============================================================================

drop policy if exists "timeline_owner_insert" on report_timeline;
create policy "timeline_owner_insert" on report_timeline for insert with check (
  auth_is_approved()
  and auth.uid() = (select reporter_id from reports where id = report_id)
);

drop policy if exists "map_incidents_owner_insert" on map_incidents;
create policy "map_incidents_owner_insert" on map_incidents for insert with check (
  auth_is_approved()
  and exists (
    select 1 from reports r
    where r.id = report_id and r.reporter_id = auth.uid()
  )
);
