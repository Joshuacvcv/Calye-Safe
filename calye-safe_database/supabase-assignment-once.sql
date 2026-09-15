-- ============================================================================
-- Calye-Safe — one ACTIVE assignment per report
--
-- PROBLEM THIS SOLVES: repeated Dispatch clicks (or repeated modal opens)
-- created duplicate `assigned` rows for the same report (e.g. three active
-- rows for one report_no), which duplicated responder queue entries.
--
-- WHAT IT DOES:
--   1. Deletes duplicate active assignments, keeping the earliest-created
--      one per report.
--   2. Adds a partial unique index so the database itself rejects a second
--      active assignment for the same report, no matter which client tries.
--      Resolved assignments are excluded, so a closed report CAN be
--      re-dispatched later if needed.
--
-- HOW TO USE: paste the whole file into the Supabase SQL Editor and RUN.
-- Idempotent — safe to re-run.
-- ============================================================================

-- ── 1. Remove existing duplicate active assignments (keep earliest) ─────────
delete from assignments a using assignments b
where a.report_id = b.report_id
  and a.report_id is not null
  and a.status <> 'resolved' and b.status <> 'resolved'
  and (a.created_at, a.id) > (b.created_at, b.id);

-- ── 2. Enforce single active assignment per report at the DB level ──────────
create unique index if not exists uq_assignments_active_per_report
  on assignments (report_id)
  where status <> 'resolved' and report_id is not null;


-- ── 3. VERIFICATION ─────────────────────────────────────────────────────────
-- Expect: zero rows (no report with 2+ active assignments).
-- select report_id, count(*)
-- from assignments
-- where status <> 'resolved' and report_id is not null
-- group by report_id
-- having count(*) > 1;
