-- ============================================================================
-- CALYE-SAFE — Fix: notifications triggers vs. RLS
--
-- PROBLEM:
--   notify_report_status_change() and notify_new_assignment() run as the
--   invoking user (the anon key in demo). RLS on `notifications` blocks their
--   INSERTs, so EVERY status UPDATE on a report (admin dispatch / resolve /
--   verify) fails with:
--       "new row violates row-level security policy for table notifications"
--
--   The apps' CalyeDB.update() swallows the error and returns null, so the
--   report status change silently never persists — the whole flow breaks.
--
-- FIX:
--   1. Recreate both trigger functions as SECURITY DEFINER (run as the
--      function owner = postgres) so they can always insert notifications,
--      regardless of who performed the UPDATE. Works with RLS ON (production)
--      and RLS OFF (demo).
--   2. Additionally disable RLS on `notifications` for the demo (belt + braces).
--
-- Safe to re-run. Run in Supabase > SQL Editor after supabase-fixes.sql.
-- ============================================================================

-- ── 1. Report status-change notifications (SECURITY DEFINER) ────────────────
create or replace function public.notify_report_status_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_title text;
  v_body text;
  v_type text;
begin
  if old.status is distinct from new.status then
    case new.status
      when 'verified' then
        v_title := 'Report Verified';
        v_body := 'Your report #' || new.report_no || ' has been verified by barangay staff.';
        v_type := 'update';
      when 'responding' then
        v_title := 'Responder Dispatched';
        v_body := 'A responder unit is on the way to your reported location.';
        v_type := 'update';
      when 'on_site' then
        v_title := 'Responder On-Site';
        v_body := 'The responder has arrived at the location.';
        v_type := 'update';
      when 'resolved' then
        v_title := 'Report Resolved';
        v_body := 'Your report #' || new.report_no || ' has been resolved.';
        v_type := 'update';
      else
        v_title := 'Report Status Updated';
        v_body := 'Your report #' || new.report_no || ' status changed to ' || new.status || '.';
        v_type := 'update';
    end case;

    if new.reporter_id is not null then
      insert into public.notifications (user_id, title, body, type, related_report_id)
      values (new.reporter_id, v_title, v_body, v_type, new.id);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_report_status on reports;
create trigger trg_notify_report_status
  after update on reports
  for each row execute function public.notify_report_status_change();


-- ── 2. New-assignment notifications (SECURITY DEFINER) ──────────────────────
create or replace function public.notify_new_assignment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_profile_id uuid;
begin
  if tg_op = 'INSERT' then
    select id into v_profile_id
    from public.profiles
    where unit_id = (
      select unit_id from public.responders where id = new.responder_id
    );

    if v_profile_id is not null then
      insert into public.notifications (user_id, title, body, type, related_report_id, related_assignment_id)
      select v_profile_id,
             'New Assignment',
             'You have been assigned to report #' || r.report_no || ': ' || r.type,
             'alert',
             r.id,
             new.id
      from public.reports r where r.id = new.report_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_new_assignment on assignments;
create trigger trg_notify_new_assignment
  after insert on assignments
  for each row execute function public.notify_new_assignment();


-- ── 3. Demo belt-and-braces: turn RLS off on notifications ──────────────────
alter table public.notifications disable row level security;
