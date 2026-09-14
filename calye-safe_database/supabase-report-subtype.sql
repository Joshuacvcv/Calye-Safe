-- ============================================================================
-- Calye-Safe — report specific-incident subtype column
-- The resident app (step 3) now asks for the SPECIFIC incident
-- (e.g. "Flash floods / rising floodwater (baha)") within the chosen
-- incident group. Run this once in the Supabase SQL Editor so reports
-- can store it in its own column.
--
-- Safe to run multiple times (IF NOT EXISTS). No existing data is touched.
-- If you skip this file, the app still works: it folds the subtype into
-- the description text on insert instead.
-- ============================================================================

alter table reports
  add column if not exists subtype text default null;

comment on column reports.subtype is
  'Specific incident chosen on report step 3 (e.g. "Residential house fires"). Null for reports filed before the taxonomy update.';
