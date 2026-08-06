-- ============================================================================
-- Calye-Safe — REPORT AUTO-SYNC TRIGGERS: SECURITY DEFINER FIX
--
-- Filing a report failed with:
--   new row violates row-level security policy for table "report_timeline"
--
-- WHY: trg_create_report_timeline / trg_sync_map_incidents were plain
-- plpgsql (invoker rights), so when an APPROVED RESIDENT inserted a report
-- the AFTER INSERT trigger ran AS THE RESIDENT and tried to write
-- report_timeline / map_incidents — both of which only allow staff inserts.
-- The trigger's own write was rejected by RLS, failing the whole insert.
--
-- FIX: run these trigger functions as their owner (SECURITY DEFINER) so the
-- derived timeline + map-incident rows are written without hitting RLS.
-- The functions only write rows DERIVED from the just-inserted report row,
-- so no data is exposed; the security-definer owner bypasses the policies.
--
-- RUN IN THE SUPABASE SQL EDITOR. Safe to re-run.
-- ============================================================================

alter function public.create_report_timeline()
  security definer set search_path = public;

alter function public.sync_map_incidents_from_report()
  security definer set search_path = public;

alter function public.create_assignment_timeline()
  security definer set search_path = public;
