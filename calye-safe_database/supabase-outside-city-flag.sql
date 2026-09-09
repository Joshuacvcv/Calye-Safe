-- ============================================================================
-- OUTSIDE-SANTA-ROSA FLAG ON REPORTS
-- ============================================================================
-- The resident pins the incident location on the Step 2 map. When that point
-- falls outside the Santa Rosa city boundary (santarosa-boundary.js), the
-- report records outside_city = true and the resident sees a warning;
-- out-of-bounds incidents are also filtered from the public incident map.
--
-- Run this once in the Supabase SQL Editor.
-- ============================================================================

alter table public.reports
  add column if not exists outside_city boolean not null default false;

comment on column public.reports.outside_city is
  'True when the pinned incident location fell outside the Santa Rosa boundary';