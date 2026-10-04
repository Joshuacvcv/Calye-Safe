-- ============================================================================
-- Calye-Safe — AUDIT LOG (who did what, when)
--
-- WHY:
--   Staff can approve/reject verifications and permanently delete accounts,
--   but nothing records WHICH staffer did it. This adds an append-only log:
--   every privileged RPC writes one row (actor, action, target, detail).
--
-- SAFETY:
--   * New table only — no existing table or function is altered in place.
--   * The two admin RPCs are redefined with their exact current bodies plus
--     one audit insert each (copied verbatim from supabase-admin-verify-rpc.sql
--     and supabase-admin-delete-user-rpc.sql). Behavior is otherwise identical.
--   * Rows can never be edited or deleted through the API (RLS allows INSERT
--     for authenticated + SELECT for staff only; no UPDATE/DELETE policies).
--   * Safe to re-run.
--
-- RUN IN THE SUPABASE SQL EDITOR (after the two admin RPC files).
-- ============================================================================

-- 1. Append-only table. No foreign keys on purpose: the target row may be
--    deleted right after (delete-user), and the log must survive that.
create table if not exists public.audit_log (
  id         bigint generated always as identity primary key,
  happened_at timestamptz not null default now(),
  actor_id   uuid,
  actor_email text not null default '',
  action     text not null,
  target_id  uuid,
  detail     text not null default ''
);

alter table public.audit_log enable row level security;

-- Authenticated users may write (only via the definer RPCs below, which run
-- as the table owner anyway). Nobody may change history.
drop policy if exists audit_log_staff_select on public.audit_log;
create policy audit_log_staff_select
  on public.audit_log for select
  to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role in ('staff', 'admin')
    )
  );

-- No INSERT/UPDATE/DELETE policies: direct API writes are denied entirely.
-- The definer helper below bypasses RLS, same pattern as the admin RPCs.

-- 2. Definer helper: the single choke point for writing audit rows.
create or replace function public.audit_write(
  p_action text,
  p_target uuid default null,
  p_detail text default ''
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := '';
begin
  if auth.uid() is null then
    return;
  end if;
  select coalesce(p.email, '') into v_email
    from public.profiles p where p.id = auth.uid();
  insert into public.audit_log (actor_id, actor_email, action, target_id, detail)
  values (auth.uid(), v_email, p_action, p_target, coalesce(p_detail, ''));
end;
$$;

revoke execute on function public.audit_write(text, uuid, text) from public, anon;
grant  execute on function public.audit_write(text, uuid, text) to authenticated;

-- 3. admin_review_verification + audit line (body copied verbatim, +1 insert).
create or replace function public.admin_review_verification(
  p_request_id uuid,
  p_decision   text,
  p_note       text default ''
)
returns table (ok boolean, message text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_is_staff boolean;
  v_status  public.verification_status;
begin
  if auth.uid() is null then
    return query select false, 'Not authenticated.'::text; return;
  end if;

  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role in ('staff', 'admin')
  ) into v_is_staff;

  if not v_is_staff then
    return query select false,
      'Admin privileges required. uid=' || coalesce(auth.uid()::text, '<null>')
      || ' role=' || coalesce((select role::text from public.profiles where id = auth.uid()), '<no-profile-row>');
    return;
  end if;

  if lower(trim(p_decision)) not in ('approved', 'rejected') then
    return query select false, 'Invalid decision.'; return;
  end if;
  v_status := lower(trim(p_decision))::public.verification_status;

  select user_id into v_user_id
    from public.verification_requests
   where id = p_request_id;

  if v_user_id is null then
    return query select false, 'Verification request not found.'; return;
  end if;

  update public.verification_requests
     set status      = v_status,
         review_note = coalesce(p_note, ''),
         reviewed_at = now(),
         reviewed_by = auth.uid()
   where id = p_request_id;

  update public.profiles
     set verification_status = v_status,
         verified_at         = case when v_status = 'approved' then now() else verified_at end
   where id = v_user_id;

  if v_status = 'rejected' then
    update public.profiles set id_doc_url = null where id = v_user_id;
  end if;

  -- Audit: who reviewed whom, how, and why. Runs as definer (bypasses RLS).
  perform public.audit_write(
    'verification.' || v_status::text,
    v_user_id,
    'request=' || p_request_id::text || ' note=' || coalesce(p_note, '')
  );

  return query select true, 'Request reviewed as ' || v_status::text;
end;
$$;

revoke execute on function public.admin_review_verification(uuid, text, text) from public, anon;
grant  execute on function public.admin_review_verification(uuid, text, text) to authenticated;

-- 4. admin_delete_user + audit line (body copied verbatim, +1 insert before
--    the delete so the actor is recorded even though the target vanishes).
create or replace function public.admin_delete_user(p_target uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_is_staff    boolean;
  v_target_role text;
  v_target_email text;
begin
  if auth.uid() is null then
    return query select false, 'Not authenticated.'; return;
  end if;

  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role in ('staff', 'admin')
  ) into v_is_staff;

  if not v_is_staff then
    return query select false, 'Admin privileges required.'; return;
  end if;

  if p_target is null then
    return query select false, 'No account specified.'; return;
  end if;

  if p_target = auth.uid() then
    return query select false, 'You cannot delete your own account.'; return;
  end if;

  select role::text, coalesce(email, '') into v_target_role, v_target_email
    from public.profiles where id = p_target;

  if v_target_role is null then
    return query select false, 'Account not found.'; return;
  end if;

  if v_target_role in ('staff', 'admin') then
    return query select false, 'Staff/admin accounts cannot be deleted.'; return;
  end if;

  -- Audit BEFORE the delete (the profile row is about to disappear).
  perform public.audit_write(
    'account.deleted',
    p_target,
    'role=' || v_target_role || ' email=' || v_target_email
  );

  alter table public.reports       disable trigger trg_reports_geom;
  alter table public.reports       disable trigger trg_sync_map_incidents;
  alter table public.map_incidents disable trigger trg_map_incidents_geom;

  begin
    update public.reports set reporter_id = null where reporter_id = p_target;
    delete from auth.users where id = p_target;
  exception when others then
    alter table public.reports       enable trigger trg_reports_geom;
    alter table public.reports       enable trigger trg_sync_map_incidents;
    alter table public.map_incidents enable trigger trg_map_incidents_geom;
    raise;
  end;

  alter table public.reports       enable trigger trg_reports_geom;
  alter table public.reports       enable trigger trg_sync_map_incidents;
  alter table public.map_incidents enable trigger trg_map_incidents_geom;

  return query select true, 'Account deleted permanently.';
end;
$$;

revoke execute on function public.admin_delete_user(uuid) from public, anon;
grant  execute on function public.admin_delete_user(uuid) to authenticated;
