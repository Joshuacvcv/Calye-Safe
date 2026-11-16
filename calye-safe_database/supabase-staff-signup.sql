-- ============================================================================
-- Calye-Safe — STAFF SIGN-UP (public form + city-admin approval)
--
-- WHY:
--   Barangay staff accounts are now requested through the same public
--   "Create Account" form the residents use (calye-safe-admins.html gate),
--   instead of being hand-created in the Supabase dashboard.
--
--   The flow and its safety properties:
--
--     1. The applicant signs up. handle_new_user() creates the profile as
--        role = 'resident' / verification_status = 'pending' — the client
--        canNOT choose its own role (raw_user_meta_data is ignored for
--        anything except 'responder'), so a public form can never
--        self-promote.
--     2. The form files a verification_requests row with role = 'staff'
--        (plus the chosen barangay on the profile) via CalyeAuth.
--     3. The city admin reviews it in the existing Verify-Users queue and
--        presses Approve — exactly like any resident/responder request.
--     4. THIS FUNCTION then promotes the profile to role = 'staff'.
--
--   Until step 4 the account holds no privilege at all: auth_is_staff() is
--   role-based, so a 'pending' resident can neither read other profiles nor
--   approve itself through profiles_staff_update.
--
--   The requested barangay is read from profiles.barangay, which the sign-up
--   form writes at step 2. It is guaranteed non-empty on approval because a
--   staff profile with an empty barangay would fall back to the city-wide
--   view (adminScope = null) and see every barangay's reports.
--
-- RUN IN THE SUPABASE SQL EDITOR (after supabase-admin-verify-rpc.sql and
-- supabase-audit-log.sql — this replaces admin_review_verification with the
-- audited body + the staff promotion).
-- Safe to re-run.
-- ============================================================================

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
  v_user_id  uuid;
  v_is_staff boolean;
  v_status   public.verification_status;
  v_req_role public.user_role;
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

  select user_id, role into v_user_id, v_req_role
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

  -- ── STAFF PROMOTION ────────────────────────────────────────────────────────
  -- A request filed with role = 'staff' is what turns the pending resident
  -- into a barangay account. Only 'staff' is ever granted here: 'admin' can
  -- only be created from the Supabase dashboard, so this path can never be
  -- used to escalate to city-wide rights.
  if v_status = 'approved' and v_req_role = 'staff' then
    update public.profiles
       set role              = 'staff',
           verification_status = 'approved',
           -- a staff row with no barangay would scope to the whole city
           barangay          = coalesce(nullif(btrim(barangay), ''), 'Barangay Calye')
     where id = v_user_id
       and role <> 'admin';          -- never demote a city administrator
  end if;

  -- A rejected/re-requested staff applicant must not keep a privileged role
  -- from an earlier approval: drop them back to resident on rejection.
  if v_status = 'rejected' and v_req_role = 'staff' then
    update public.profiles
       set role = 'resident'
     where id = v_user_id
       and role = 'staff';
  end if;

  -- Also clear the stored ID on rejection so a stale file isn't re-approved.
  if v_status = 'rejected' then
    update public.profiles set id_doc_url = null where id = v_user_id;
  end if;

  -- Audit: who reviewed whom, how, and why. Runs as definer (bypasses RLS).
  perform public.audit_write(
    'verification.' || v_status::text,
    v_user_id,
    'request=' || p_request_id::text || ' role=' || coalesce(v_req_role::text, '?')
      || ' note=' || coalesce(p_note, '')
  );

  return query select true, 'Request reviewed as ' || v_status::text
    || case when v_status = 'approved' and v_req_role = 'staff'
            then ' (staff account activated)' else '' end;
end;
$$;

revoke execute on function public.admin_review_verification(uuid, text, text) from public, anon;
grant  execute on function public.admin_review_verification(uuid, text, text) to authenticated;
