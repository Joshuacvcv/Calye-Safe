-- ============================================================================
-- Calye-Safe — ADMIN DELETE USER RPC
--
-- Allows a staff/admin to permanently remove a resident (or responder) account.
-- Deleting the row in `auth.users` cascades to `profiles` (id references
-- auth.users on delete cascade) and in turn to verification_requests, etc.
-- Incidents stay but become anonymous (reporter_id is set null).
--
-- SECURITY:
--   * SECURITY DEFINER so it can delete from auth.users (bypasses RLS).
--   * Authorization is enforced explicitly: caller must be staff/admin.
--   * Cannot delete yourself, and staff/admin accounts are protected so the
--     team can't be wiped out.
--   * Granted to `authenticated` only; anon/public are never allowed.
--
-- RUN IN THE SUPABASE SQL EDITOR. Safe to re-run.
-- ============================================================

create or replace function public.admin_delete_user(p_target uuid)
returns table (ok boolean, message text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_is_staff    boolean;
  v_target_role text;
begin
  -- Must be a signed-in staff/admin.
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

  -- Reject self-deletion and protect fellow staff/admins.
  if p_target = auth.uid() then
    return query select false, 'You cannot delete your own account.'; return;
  end if;

  select role::text into v_target_role from public.profiles where id = p_target;

  if v_target_role is null then
    return query select false, 'Account not found.'; return;
  end if;

  if v_target_role in ('staff', 'admin') then
    return query select false, 'Staff/admin accounts cannot be deleted.'; return;
  end if;

  -- Deleting a profile sets reports.reporter_id = NULL (ON DELETE), which
  -- fires trg_sync_map_incidents (AFTER UPDATE on reports). That trigger calls
  -- ST_MakePoint to recompute geom — but this RPC runs with set search_path='',
  -- so the PostGIS function can't be resolved and the whole delete fails with
  -- 42883 ("function st_makepoint does not exist"). Disable the map-sync
  -- triggers for the duration of the delete; the incident points are preserved
  -- and simply become anonymous. Triggers are re-enabled even on error.
  alter table public.reports      disable trigger trg_sync_map_incidents;
  alter table public.map_incidents disable trigger trg_map_incidents_geom;

  begin
    -- Anonymize this account's reports (points are kept, reporter removed).
    update public.reports set reporter_id = null where reporter_id = p_target;
    -- Permanently remove the account and everything cascading from it.
    delete from auth.users where id = p_target;
  exception when others then
    alter table public.reports      enable trigger trg_sync_map_incidents;
    alter table public.map_incidents enable trigger trg_map_incidents_geom;
    raise;
  end;

  alter table public.reports      enable trigger trg_sync_map_incidents;
  alter table public.map_incidents enable trigger trg_map_incidents_geom;

  return query select true, 'Account deleted permanently.';
end;
$$;

revoke execute on function public.admin_delete_user(uuid) from public, anon;
grant  execute on function public.admin_delete_user(uuid) to authenticated;