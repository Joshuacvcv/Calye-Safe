-- ============================================================================
-- Calye-Safe — FIX: responder profiles sharing the same unit_id
--
-- SYMPTOM:
--   Users tab counts every role='responder' profile, but Responder Performance
--   shows fewer rows because the UI merges by unit_id and drops the 2nd+
--   account that claims the same unit (e.g. two profiles both on RES-001).
--
-- THIS SCRIPT:
--   1. Keeps the EARLIEST profile on each duplicated unit_id.
--   2. Moves every later duplicate to the next free RES-xxx number
--      (numbering considers BOTH profiles and responders, so no collisions).
--   3. Backfills missing rows in `responders` for every profile unit_id so
--      the units table and the profiles table line up again.
--
-- RUN IN THE SUPABASE SQL EDITOR. Safe to re-run.
-- ============================================================================

-- 1 + 2: reassign duplicate unit holders (newest on each unit_id moves) -------
with ranked as (
  select id, unit_id,
         row_number() over (
           partition by unit_id
           order by created_at asc, id asc
         ) as rn
  from public.profiles
  where role = 'responder'
    and unit_id is not null
    and unit_id <> ''
),
dupes as (
  select id from ranked where rn > 1
),
all_nums as (
  select (regexp_replace(unit_id, '\D', '', 'g'))::int as n
  from public.responders
  where unit_id ~ '^RES-[0-9]+$'
  union all
  select (regexp_replace(unit_id, '\D', '', 'g'))::int
  from public.profiles
  where role = 'responder' and unit_id ~ '^RES-[0-9]+$'
),
next_free as (
  select coalesce(max(n), 0) + 1 as start_n from all_nums
),
numbered as (
  select d.id,
         'RES-' || lpad((nf.start_n + row_number() over (order by d.id) - 1)::text, 3, '0') as new_unit
  from dupes d
  cross join next_free nf
)
update public.profiles p
set unit_id = n.new_unit
from numbered n
where p.id = n.id;

-- 3: ensure every distinct profile unit_id has a responders row ---------------
insert into public.responders (unit_id, name, vehicle, agency)
select distinct p.unit_id, p.full_name, '', 'Barangay Calye QRT'
from public.profiles p
where p.role = 'responder'
  and p.unit_id is not null
  and p.unit_id <> ''
  and not exists (
    select 1 from public.responders r where r.unit_id = p.unit_id
  )
on conflict (unit_id) do nothing;

-- VERIFY: profiles should have unique non-null unit_ids; counts should match --
select unit_id, count(*)
from public.profiles
where role = 'responder'
group by unit_id
having count(*) > 1;

select p.full_name, p.email, p.unit_id
from public.profiles p
where p.role = 'responder'
order by p.unit_id, p.created_at;

select r.unit_id, r.name
from public.responders r
order by r.unit_id;
