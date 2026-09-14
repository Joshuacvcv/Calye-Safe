-- ============================================================================
-- Calye-Safe — Data-driven Analytics layer (Objective C)
--
--   Run AFTER supabase-schema.sql (and supabase-seed.sql for demo data).
--   Provides:
--     1. v_incident_density      — grid-bucketed incident view (approx 400 m cells)
--     2. fn_incident_summary()   — JSON summary: totals, by-category, monthly
--                                  trend, hotspots, severity, avg resolution hrs
--     3. fn_incident_density()   — weighted heatmap points (grid centroids)
--     4. monthly_reports         — snapshot table for automated monthly reports
--     5. fn_monthly_summary()    — generates a month's report on demand
--     6. (commented) pg_cron job — auto-generates the previous month's report
--
--   All functions are SECURITY DEFINER so they keep working after RLS is
--   enabled; only anon / authenticated are granted EXECUTE.
-- ============================================================================


-- ============================================================================
-- 1. GRID DENSITY VIEW (drives the heatmap + hotspot queries)
--    Buckets report coordinates into ~0.004° cells (~400 m at this latitude).
-- ============================================================================
create or replace view v_incident_density as
  select
    round((r.lat / 0.004)) * 0.004 as lat,
    round((r.lng / 0.004)) * 0.004 as lng,
    count(*)                                          as incident_count,
    count(*) filter (where r.severity = 'major')      as major_count,
    count(*) filter (where r.severity = 'minor')      as minor_count,
    count(*) filter (where r.status  = 'resolved')    as resolved_count
  from reports r
  group by 1, 2;


-- ============================================================================
-- 2. INCIDENT SUMMARY (JSON) — powers stat cards, trends, insights
--    p_from / p_to are timestamps; NULL p_from means "all time".
-- ============================================================================
create or replace function fn_incident_summary(p_from timestamptz default null, p_to timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from timestamptz;
  v_to   timestamptz;
  v_total         bigint;
  v_open          bigint;
  v_resolved      bigint;
  v_major         bigint;
  v_minor         bigint;
  v_avg_res_hrs   numeric;
  result          jsonb;
begin
  v_from := coalesce(p_from, '1970-01-01'::timestamptz);
  v_to   := coalesce(p_to, now());

  select
    count(*),
    count(*) filter (where status <> 'resolved'),
    count(*) filter (where status  = 'resolved'),
    count(*) filter (where severity = 'major'),
    count(*) filter (where severity = 'minor')
  into v_total, v_open, v_resolved, v_major, v_minor
  from reports
  where created_at between v_from and v_to;

  select round(avg(extract(epoch from (a.resolved_at - r.created_at)) / 3600.0)::numeric, 1)
  into v_avg_res_hrs
  from assignments a
  join reports r on r.id = a.report_id
  where r.created_at between v_from and v_to
    and a.resolved_at is not null;

  result := jsonb_build_object(
    'range', jsonb_build_object('from', v_from, 'to', v_to),
    'totals', jsonb_build_object(
      'total',    v_total,
      'open',     v_open,
      'resolved', v_resolved
    ),
    'by_severity', jsonb_build_object('major', v_major, 'minor', v_minor),
    'avg_resolution_hrs', coalesce(v_avg_res_hrs, 0),

    -- per-category counts + share of the range total
    'by_category', coalesce((
      select jsonb_agg(jsonb_build_object(
               'category', s.category,
               'count',    s.cnt,
               'pct',      round((100.0 * s.cnt) / nullif(v_total, 0), 1)
             ) order by s.cnt desc)
      from (
        select category, count(*) as cnt
        from reports
        where created_at between v_from and v_to
        group by category
      ) s
    ), '[]'::jsonb),

    -- last 6 months (includes empty months)
    'monthly', coalesce((
      select jsonb_agg(jsonb_build_object(
               'label', to_char(m, 'Mon'),
               'key',   to_char(m, 'YYYY-MM'),
               'count', coalesce(c.cnt, 0)
             ) order by m)
      from generate_series(
             date_trunc('month', now()) - interval '5 months',
             date_trunc('month', now()),
             interval '1 month'
           ) m
      left join (
        select date_trunc('month', created_at) as month, count(*) as cnt
        from reports
        group by 1
      ) c on c.month = m
    ), '[]'::jsonb),

    -- top 5 recurring locations
    'hotspots', coalesce((
      select jsonb_agg(jsonb_build_object(
               'location', s.location,
               'count',    s.cnt
             ) order by s.cnt desc)
      from (
        select location, count(*) as cnt
        from reports
        where created_at between v_from and v_to
          and location <> ''
        group by location
        order by cnt desc
        limit 5
      ) s
    ), '[]'::jsonb)
  );

  return result;
end;
$$;

revoke all on function fn_incident_summary(timestamptz, timestamptz) from public;
grant execute on function fn_incident_summary(timestamptz, timestamptz) to anon, authenticated, service_role;


-- ============================================================================
-- 3. WEIGHTED HEATMAP POINTS — grid centroids with a severity-weighted value.
--    weight = count * (1 + 0.5 * major_share) so hotspots with majors glow hotter.
-- ============================================================================
create or replace function fn_incident_density(p_from timestamptz default null, p_to timestamptz default null)
returns table (lat double precision, lng double precision, weight numeric, incidents bigint)
language sql
security definer
set search_path = public
as $$
  select
    round((r.lat / 0.004)) * 0.004 as lat,
    round((r.lng / 0.004)) * 0.004 as lng,
    round((
      count(*) * (1 + 0.5 * count(*) filter (where r.severity = 'major') / nullif(count(*), 0))
    )::numeric, 2) as weight,
    count(*) as incidents
  from reports r
  where r.lat between 14.25 and 14.35
    and r.lng between 121.04 and 121.15
    and r.created_at between coalesce(p_from, '1970-01-01'::timestamptz) and coalesce(p_to, now())
  group by 1, 2
$$;

revoke all on function fn_incident_density(timestamptz, timestamptz) from public;
grant execute on function fn_incident_density(timestamptz, timestamptz) to anon, authenticated, service_role;


-- ============================================================================
-- 4. MONTHLY REPORT SNAPSHOTS
-- ============================================================================
create table if not exists monthly_reports (
  id            uuid primary key default gen_random_uuid(),
  report_month  date not null unique,
  summary       jsonb not null,
  generated_at  timestamptz not null default now()
);


-- ============================================================================
-- 5. ON-DEMAND MONTHLY SUMMARY
--    fn_monthly_summary(p_year, p_month) -> jsonb
--    Returns the fn_incident_summary() for the given calendar month plus
--    report_month / generated_at metadata. The UI calls this from the
--    "Automated Monthly Report" button.
-- ============================================================================
create or replace function fn_monthly_summary(p_year int, p_month int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from   timestamptz;
  v_to     timestamptz;
  v_summary jsonb;
begin
  -- Construct UTC midnight of 1st day of month (avoid timezone shift from make_timestamptz)
  v_from := (p_year || '-' || lpad(p_month::text, 2, '0') || '-01 00:00:00+00')::timestamptz;
  v_to   := v_from + interval '1 month';

  select public.fn_incident_summary(v_from, v_to) into v_summary;

  return jsonb_build_object(
    'report_month', to_char(v_from, 'YYYY-MM'),
    'report_label', to_char(v_from, 'FMMonth YYYY'),
    'generated_at', now(),
    'summary', v_summary
  );
end;
$$;

revoke all on function fn_monthly_summary(int, int) from public;
grant execute on function fn_monthly_summary(int, int) to anon, authenticated, service_role;


-- ============================================================================
-- 5b. RESPONDER MONTHLY PERFORMANCE
--    fn_responder_monthly_performance(p_year, p_month) -> jsonb
--    Returns per-responder performance metrics for the given calendar month.
--    The UI calls this from the "Responder Performance" button.
-- ============================================================================
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
  -- Sourced from responder PROFILES so every registered responder appears,
  -- even with no unit row or no jobs yet. Orphan unit rows (no profile)
  -- are appended too, so nothing ever goes missing.
  performer_data as (
    select
      coalesce(u.rid, u.pid) as responder_id,
      coalesce(nullif(u.unit_id, ''), 'Unassigned') as unit_id,
      coalesce(nullif(u.pname, ''), nullif(u.rname, ''), 'Responder') as name,
      coalesce(u.vehicle, '') as vehicle,
      coalesce(u.agency, 'Barangay Calye QRT') as agency,
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
    from (
      select p.id as pid, p.full_name as pname, p.unit_id as unit_id,
             r.id as rid, r.name as rname, r.vehicle as vehicle, r.agency as agency
      from profiles p
      left join responders r
        on r.unit_id = p.unit_id and p.unit_id is not null and p.unit_id <> ''
      where p.role = 'responder'
      union
      select null as pid, null as pname, r.unit_id as unit_id,
             r.id as rid, r.name as rname, r.vehicle as vehicle, r.agency as agency
      from responders r
      where not exists (
        select 1 from profiles p
        where p.role = 'responder'
          and p.unit_id is not null and p.unit_id <> ''
          and p.unit_id = r.unit_id
      )
    ) u
    left join assignment_stats s on s.responder_id = u.rid
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


-- ============================================================================
-- 6. AUTOMATED GENERATION (optional)
--    Supabase has pg_cron enabled by default. Uncomment + run to auto-generate
--    the previous month's report on the 1st of every month at 08:00.
-- ============================================================================
-- select cron.schedule('calye-monthly-report', '0 8 1 * *', $cron$
--   insert into monthly_reports (report_month, summary)
--   values (
--     date_trunc('month', now()) - interval '1 month',
--     public.fn_monthly_summary(
--       extract(year  from date_trunc('month', now()) - interval '1 month')::int,
--       extract(month from date_trunc('month', now()) - interval '1 month')::int
--     )
--   )
--   on conflict (report_month) do update
--     set summary = excluded.summary, generated_at = now();
-- $cron$);
