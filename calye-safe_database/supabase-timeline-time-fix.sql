-- ============================================================================
-- FIX: assignment_timeline "Reported" timestamp
-- ----------------------------------------------------------------------------
-- Problem: The trigger created step 1 (Reported) with the ASSIGNMENT's
-- created_at (= dispatch moment), and the admin app also seeded the same two
-- steps with the same dispatch time, so the responder rail showed
-- "Reported" and "Verified & Assigned to you" both at the dispatch moment.
--
-- Fix: 1) update the trigger so step 1 reflects the resident's reports.created_at
--      2) repair already-written rows so their step 1 uses the real filing time.
-- Run this whole script in the Supabase SQL editor.
-- ============================================================================

-- 1. Rebuild the auto-sync trigger with the correct "Reported" time.
-- SECURITY DEFINER so writes from resident-triggered inserts don't trip RLS.
create or replace function create_assignment_timeline()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_created_at timestamptz;
begin
  select r.created_at into v_created_at from reports r where r.id = new.report_id;
  v_created_at := coalesce(v_created_at, new.created_at);

  insert into assignment_timeline (assignment_id, step, label, happened_at, state)
  values
    (new.id, 1, 'Reported', to_char(v_created_at at time zone 'Asia/Manila', 'Mon DD · HH:MI AM'), 'done'),
    (new.id, 2, 'Verified & Assigned to you', to_char(coalesce(new.assigned_at, new.created_at) at time zone 'Asia/Manila', 'Mon DD · HH:MI AM'), 'done'),
    (new.id, 3, 'En Route', '—', 'pending'),
    (new.id, 4, 'On-Site', '—', 'pending'),
    (new.id, 5, 'Resolved', '—', 'pending');
  return new;
end $$;

drop trigger if exists trg_create_assignment_timeline on assignments;
create trigger trg_create_assignment_timeline
  after insert on assignments
  for each row execute function create_assignment_timeline();

-- 2. Repair existing rows: point step 1 at the report's real filing time.
update assignment_timeline t
set happened_at = to_char(r.created_at, 'Mon DD · HH:MI AM')
from assignments a
join reports r on r.id = a.report_id
where t.assignment_id = a.id
  and t.step = 1
  and t.happened_at is distinct from to_char(r.created_at, 'Mon DD · HH:MI AM');

-- 3. Verify: every assignment's step-1 time should now differ from step 2.
select a.id as assignment_id,
       t1.happened_at as reported,
       t2.happened_at as verified_assigned
from assignments a
left join assignment_timeline t1 on t1.assignment_id = a.id and t1.step = 1
left join assignment_timeline t2 on t2.assignment_id = a.id and t2.step = 2
order by a.created_at desc
limit 20;