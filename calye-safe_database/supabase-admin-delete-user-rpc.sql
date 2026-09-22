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

-- Harden the shared BEFORE-UPDATE geom trigger first: admin_delete_user runs
-- with set search_path='', and update_geom_from_latlng used to inherit that
-- empty path — ST_MakePoint then fails with 42883 on the reporter_id NULL-out.
-- Giving the trigger its own search_path fixes this class of bug for every
-- caller, not just this RPC. CREATE OR REPLACE keeps the OID, so existing
-- triggers (trg_reports_geom / trg_responders_geom / trg_map_incidents_geom)
-- keep pointing at it.
create or replace function public.update_geom_from_latlng()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.lat is not null and new.lng is not null then
    new.geom = ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326);
  end if;
  return new;
end $$;

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

  -- The explicit reporter_id NULL-out (and the ON DELETE SET NULL from
  -- profiles) fires BOTH report triggers:
  --   * trg_reports_geom       (BEFORE UPDATE) — was the 42883 culprit; also
  --     hardened above via update_geom_from_latlng's own search_path, but we
  --     still skip it here: lat/lng don't change, so geom needs no recompute.
  --   * trg_sync_map_incidents (AFTER UPDATE)  — map mirror, safe to pause;
  --     map_incidents rows are anonymized via the profile cascade instead.
  -- trg_map_incidents_geom is disabled for the auth.users cascade as well.
  -- Triggers are re-enabled even when the delete errors.
  alter table public.reports       disable trigger trg_reports_geom;
  alter table public.reports       disable trigger trg_sync_map_incidents;
  alter table public.map_incidents disable trigger trg_map_incidents_geom;

  begin
    -- Anonymize this account's reports (points are kept, reporter removed).
    update public.reports set reporter_id = null where reporter_id = p_target;
    -- Permanently remove the account and everything cascading from it.
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