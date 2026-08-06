-- ============================================================================
-- Calye-Safe — ADMIN REVIEW RPC (fix for 42501 on verifying a resident)
--
-- WHY:
--   The admin dashboard previously Approve/Rejected by issuing two direct
--   PostgREST UPDATEs: one on `verification_requests` and one on `profiles`.
--   The second write was intermittently blocked by the `profiles` row-level
--   security chain:
--      * `profiles_self_update` has a strict `with check` restricted to the
--        row owner (auth.uid() = id). It is NOT usable to approve someone else.
--      * `profiles_staff_update` permits the write only via `auth_is_staff()`.
--        If that helper resolves false for the caller at write time (session
--        not attached, recursively-gated subselect, or a stale non-definer
--        definition), PostgREST returns
--        `new row violates row-level security policy for table "profiles"`.
--
--   The reliable fix is to do the review as ONE `SECURITY DEFINER` function.
--   A definer function runs as its owner (which bypasses RLS on the tables it
--   touches), so the status change can NEVER be blocked by the profiles policy
--   chain. Authorization is enforced explicitly inside the function with the
--   same `auth_is_staff()` guard. Safe to re-run.
--
-- RUN IN THE SUPABASE SQL EDITOR.
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
  v_user_id uuid;
  v_is_staff boolean;
  v_status  public.verification_status;
begin
  -- Only a signed-in staff/admin may review others' verification requests.
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

  -- Validate the decision before casting.
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

  -- Also clear the stored ID on rejection so a stale file isn't re-approved.
  if v_status = 'rejected' then
    update public.profiles set id_doc_url = null where id = v_user_id;
  end if;

  return query select true, 'Request reviewed as ' || v_status::text;
end;
$$;

-- Only allow real signed-in users to run it. The anon key must always be denied.
revoke execute on function public.admin_review_verification(uuid, text, text) from public, anon;
grant  execute on function public.admin_review_verification(uuid, text, text) to authenticated;