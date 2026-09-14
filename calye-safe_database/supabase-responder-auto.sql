-- ============================================================================
-- Calye-Safe — automatic responder pipeline (profiles → responders → tab)
--
-- PROBLEM THIS SOLVES:
--   1. Responder sign-ups live in `profiles` (role='responder') with
--      unit_id = NULL, so the profiles→responders sync trigger never fires
--      and they never become dispatchable units.
--   2. fn_responder_monthly_performance only listed responders that already
--      had assignments that month, so new/quiet units were invisible.
--
-- AFTER RUNNING THIS, the chain is fully automatic:
--   signup (role=responder) → unit_id auto-assigned (RES-019, RES-020…)
--     → responders row auto-created → listed on Responder Performance tab
--     (0 jobs until first dispatch).
--
-- HOW TO USE: paste the whole file into the Supabase SQL Editor and RUN.
-- Idempotent — safe to re-run.
-- ============================================================================


-- ── 1. AUTO-ASSIGN unit_id to responder profiles that lack one ──────────────
-- BEFORE trigger (writes only NEW.unit_id, touches no other table, so it
-- cannot loop). The existing AFTER sync trigger then creates the responders
-- row from the freshly assigned unit_id.

create or replace function auto_assign_responder_unit()
returns trigger language plpgsql as $$
declare
  v_next int;
begin
  if new.role = 'responder' and (new.unit_id is null or new.unit_id = '') then
    select coalesce(max((regexp_replace(unit_id, '\D', '', 'g'))::int), 0) + 1
      into v_next
    from responders
    where unit_id ~ '^RES-[0-9]+$';
    new.unit_id := 'RES-' || lpad(v_next::text, 3, '0');
  end if;
  return new;
end $$;

drop trigger if exists trg_auto_assign_responder_unit on profiles;
create trigger trg_auto_assign_responder_unit
  before insert or update on profiles
  for each row execute function auto_assign_responder_unit();


-- ── 2. BACKFILL existing responder profiles stuck with unit_id = NULL ───────
-- Re-writing the same value still fires row triggers: the BEFORE trigger
-- above assigns the unit, then the sync trigger creates the responders row.
update profiles set unit_id = null
where role = 'responder' and unit_id is null;


-- ── 3. PERFORMANCE FUNCTION lists EVERY responder unit ─────────────────────
-- Previously aggregated FROM assignments (units with 0 jobs invisible).
-- Now starts FROM responders with a LEFT JOIN, so new units appear with 0s.

create or replace function fn_responder_monthly_performance(p_year int, p_month int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from   timestamptz;
  v_to     timestamptz;
  v_result jsonb;
begin
  -- Construct UTC midnight of 1st day of month (avoid timezone shift from make_timestamptz)
  v_from := (p_year || '-' || lpad(p_month::text, 2, '0') || '-01 00:00:00+00')::timestamptz;
  v_to   := v_from + interval '1 month';

  with assignment_stats as (
    select
      a.responder_id,
      count(*) as total_assigned,
      count(*) filter (where a.status in ('en_route', 'on_site', 'resolved', 'escalated')) as accepted,
      count(*) filter (where a.status = 'resolved') as resolved,
      count(*) filter (where a.status = 'escalated') as escalated,
      avg(extract(epoch from (a.en_route_at - a.assigned_at)) / 60) filter (where a.en_route_at is not null and a.assigned_at is not null) as avg_response_min,
      avg(extract(epoch from (a.resolved_at - a.assigned_at)) / 60) filter (where a.resolved_at is not null and a.assigned_at is not null) as avg_resolution_min
    from assignments a
    where a.created_at >= v_from
      and a.created_at < v_to
      and a.responder_id is not null
    group by a.responder_id
  ),
  performer_data as (
    select
      r.id as responder_id,
      r.unit_id,
      r.name,
      r.vehicle,
      r.agency,
      coalesce(s.total_assigned, 0) as total_assigned,
      coalesce(s.accepted, 0) as accepted,
      coalesce(s.resolved, 0) as resolved,
      coalesce(s.escalated, 0) as escalated,
      case when coalesce(s.total_assigned, 0) > 0
           then round((coalesce(s.accepted, 0)::numeric / s.total_assigned) * 100) else 0 end as acceptance_rate,
      case when coalesce(s.total_assigned, 0) > 0
           then round((coalesce(s.resolved, 0)::numeric / s.total_assigned) * 100) else 0 end as resolution_rate,
      round(coalesce(s.avg_response_min, 0)) as avg_response_min,
      round(coalesce(s.avg_resolution_min, 0)) as avg_resolution_min
    from responders r
    left join assignment_stats s on s.responder_id = r.id
  )
  select jsonb_build_object(
    'report_month', to_char(v_from, 'YYYY-MM'),
    'report_label', to_char(v_from, 'FMMonth YYYY'),
    'generated_at', now(),
    'performers', coalesce(jsonb_agg(to_jsonb(p) order by p.resolved desc, p.acceptance_rate desc), '[]'::jsonb)
  ) into v_result
  from performer_data p;

  return v_result;
end;
$$;

revoke all on function fn_responder_monthly_performance(int, int) from public;
grant execute on function fn_responder_monthly_performance(int, int) to anon, authenticated, service_role;


-- ── 4. VERIFICATION (expected: units listed, incl. zero-job units) ──────────
-- select unit_id, name from responders order by unit_id;
-- select public.fn_responder_monthly_performance(2026, 8);
