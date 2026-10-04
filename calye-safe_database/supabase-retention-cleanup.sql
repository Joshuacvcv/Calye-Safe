-- ============================================================================
-- Calye-Safe — RETENTION CLEANUP (rejected IDs older than 30 days)
--
-- WHY:
--   Rejected verification requests (and their ID photos) pile up forever.
--   NPC guidance: keep personal data only as long as needed. Rejected
--   applicants resubmit fresh rows, so deleting rejections older than 30
--   days loses nothing operational.
--
-- WHAT IT DOES (and does NOT do):
--   * Deletes `verification_requests` rows where status = 'rejected' and
--     the row is older than 30 days. Returns each deleted row's storage
--     path so the matching file can be removed from the
--     `verification-ids` bucket (see step 3 — SQL cannot delete files).
--   * Does NOT touch pending/approved rows, profiles, reports, or history.
--   * Does NOT anonymize old resolved reports: those still belong in each
--     resident's My Reports list, so removing the reporter would break the
--     app. Revisit only with an explicit product decision.
--
-- SAFETY:
--   * Dry-run first: call with true (the default) to SEE what would be
--     deleted. Nothing is removed.
--   * Staff/admin only (same guard as the other admin RPCs). Safe to re-run.
--
-- RUN IN THE SUPABASE SQL EDITOR.
-- ============================================================================

create or replace function public.retention_cleanup(p_dry_run boolean default true)
returns table (action text, target_id uuid, storage_path text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_staff boolean;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated.';
  end if;

  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role in ('staff', 'admin')
  ) into v_is_staff;

  if not v_is_staff then
    raise exception 'Admin privileges required.';
  end if;

  if coalesce(p_dry_run, true) then
    -- DRY RUN: list only.
    return query
    select 'would-delete-rejected-id'::text, vr.id, vr.id_doc_url
      from public.verification_requests vr
     where vr.status = 'rejected'
       and vr.submitted_at < now() - interval '30 days';
    return;
  end if;

  -- LIVE RUN: delete and report what went, including file paths for step 3.
  return query
  delete from public.verification_requests vr
   where vr.status = 'rejected'
     and vr.submitted_at < now() - interval '30 days'
  returning 'deleted-rejected-id'::text, vr.id, vr.id_doc_url;
end;
$$;

revoke execute on function public.retention_cleanup(boolean) from public, anon;
grant  execute on function public.retention_cleanup(boolean) to authenticated;

-- ── HOW TO USE ──────────────────────────────────────────────────────────────
-- 1. Dry run (lists candidates, deletes nothing):
--      select * from public.retention_cleanup(true);
-- 2. Live run (deletes the listed rows, returns their file paths):
--      select * from public.retention_cleanup(false);
-- 3. Remove the orphaned files shown in `storage_path` from the
--    `verification-ids` bucket (Storage > verification-ids > select > Delete).
--    Run monthly; set a calendar reminder — Supabase cron is optional.
