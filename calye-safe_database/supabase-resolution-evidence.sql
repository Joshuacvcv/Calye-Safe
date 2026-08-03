-- =============================================================================
-- RESOLUTION EVIDENCE FIX
-- Makes a responder's resolution notes + proof photo reach the admin and the
-- resident who filed the report.
--
--  1. Allow responders + staff to UPDATE the resident's report_timeline steps
--     (previously only SELECT + INSERT existed, so markReportStep silently failed).
--  2. Allow responders + staff to UPDATE their assignment_timeline steps.
--  3. Allow the report owner (resident) to SELECT the assignment linked to
--     their report, so they can view resolution_notes + proof_url.
--
-- Run this once in the Supabase SQL Editor.
-- =============================================================================

-- 1. report_timeline: responders/staff may advance & annotate timeline steps
drop policy if exists "timeline_staff_update" on report_timeline;
create policy "timeline_staff_update"
  on report_timeline for update using (auth_is_responder());

-- 2. assignment_timeline: responders/staff may advance their own steps
drop policy if exists "at_timeline_update" on assignment_timeline;
create policy "at_timeline_update"
  on assignment_timeline for update using (auth_is_responder());

-- 3. assignments: the resident who filed the report may read its assignment
drop policy if exists "assignments_owner_select" on assignments;
create policy "assignments_owner_select"
  on assignments for select using (
    exists (
      select 1 from reports r
      where r.id = assignments.report_id
        and r.reporter_id = auth.uid()
    )
  );
