-- ============================================================================
-- supabase-resident-responder-name.sql
--
-- Lets a RESIDENT see the name of the responder assigned to THEIR OWN report
-- (community app: the "My Reports" card line + the live-tracking modal).
--
-- WHY: the community app reads `assignments` for its own reports, then joins
-- assignments.responder_id → responders.id for the name. Both tables were
-- only readable through auth_is_responder() (responder / staff / admin), so a
-- resident read came back empty and the card could only say
-- "Dispatching a responder…" forever.
--
-- Two PERMISSIVE policies are added. Postgres ORs permissive policies, so
-- everything that works today keeps working — this only widens what a signed-in
-- resident may read, and only for:
--   * the assignment on a report THEY filed, and
--   * the single responder row that assignment points at.
--
-- Apply in the Supabase SQL editor. It does NOT turn RLS on or off
-- (supabase-demo-access.sql disables it); it only defines what a resident
-- may read the day RLS is enabled.
-- ============================================================================

-- 1. the assignment on a report THIS user filed
drop policy if exists "assignments_owner_select" on public.assignments;
create policy "assignments_owner_select"
  on public.assignments for select using (
    exists (
      select 1 from public.reports r
      where r.id = assignments.report_id
        and r.reporter_id = auth.uid()
    )
  );

-- 2. the responder row that assignment points at (name / vehicle / agency)
drop policy if exists "responders_assigned_select" on public.responders;
create policy "responders_assigned_select"
  on public.responders for select using (
    exists (
      select 1
      from public.assignments a
      join public.reports r on r.id = a.report_id
      where a.responder_id = responders.id
        and r.reporter_id = auth.uid()
    )
  );
