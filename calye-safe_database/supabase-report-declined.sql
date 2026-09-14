-- ============================================================================
-- Calye-Safe — allow admins to DECLINE incident reports
-- (e.g. pinned location is outside Santa Rosa City boundary)
--
-- WHY THIS FILE EXISTS: the decline flow writes status/priority =
-- 'declined' plus a resolution_notes reason on reports. Both enum types
-- lack that value and the column does not exist, so the update is rejected
-- ("Failed to decline report" in the dashboard).
--
-- HOW TO RUN (order matters):
--   1. Run STEP 1 together with anything else (transaction-safe).
--   2. Run STEP 2 ALONE (highlight just that statement + Run).
--   3. Run STEP 3 ALONE (highlight just that statement + Run).
--      (Postgres forbids ADD VALUE inside a transaction block, which is why
--      steps 2 and 3 must each run as their own single statement.)
-- Idempotent — safe to re-run.
-- ============================================================================

-- ── STEP 1: reason column (transaction-safe) ─────────────────────────────────
alter table reports
  add column if not exists resolution_notes text default '';

comment on column reports.resolution_notes is
  'Admin outcome note: decline reason, or dispatch/closure remarks. Shown to the resident.';


-- ── STEP 2: allow status = 'declined' (RUN THIS STATEMENT ALONE) ────────────
alter type report_status add value if not exists 'declined';


-- ── STEP 3: allow priority = 'declined' (RUN THIS STATEMENT ALONE) ──────────
alter type priority_level add value if not exists 'declined';
