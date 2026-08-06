-- ============================================================================
-- Calye-Safe — PRIVATE STORAGE MIGRATION (Priority 3)
--
-- Makes the two media buckets PRIVATE. Both currently contain personal data
-- (Philippine-issued government IDs + resident incident photos with GPS
-- locations), but are public = true — anyone with the URL can read them.
--
-- DESIGN DECISION:
--   Make both buckets private. Read access requires a signed URL generated
--   with a real session; only the object's owner (or staff for review) may
--   read. This aligns with RA 10173 (Data Privacy Act) expectations.
--
-- OBJECT PATHS:
--   verification-ids  /<user_uuid>/<timestamp>-id.<ext>   (owner = user_uuid)
--   evidence          /<any>                               (owner is the
--                                                           first path segment)
--
-- MUST run AFTER the apps are updated to request signed URLs / store storage
-- paths instead of public URLs (see supabase-rls-runbook). Safe to re-run.
-- ============================================================================

-- ── 1. FLIP BOTH BUCKETS TO PRIVATE -----------------------------------------
update storage.buckets set public = false
where id in ('verification-ids', 'evidence');


-- ── 2. DROP THE OLD PUBLIC/ANON STORAGE POLICIES -----------------------------
-- verification-ids (from supabase-verification.sql):
drop policy if exists "verification_ids_anon_insert" on storage.objects;
drop policy if exists "verification_ids_anon_select" on storage.objects;
drop policy if exists "verification_ids_anon_update" on storage.objects;
drop policy if exists "verification_ids_anon_delete" on storage.objects;
-- evidence (from supabase-storage-proof.sql):
drop policy if exists "evidence_proof_upload" on storage.objects;
drop policy if exists "evidence_public_read"   on storage.objects;
-- belt + braces: any other catch-all policy on these buckets:
drop policy if exists "storage_public_select" on storage.objects;
drop policy if exists "storage_public_insert" on storage.objects;
drop policy if exists "storage_public_update" on storage.objects;
drop policy if exists "storage_public_delete" on storage.objects;


-- ── 3. HELPER: is current user a staff/admin? -------------------------------
-- SECURITY DEFINER (see supabase-rls-production.sql: reading profiles from
-- within a profiles/storage policy without definer rights recurses → 54001).
create or replace function public.auth_is_staff()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role in ('staff', 'admin')
  );
$$;


-- ── 4. verification-ids  (owner upload + owner/staff read) ------------------
-- Signed URLs are issued by the client only for paths the user owns, so the
-- storage policy is the real gate. Owner check: first path segment == uid.
create policy "verification_ids_owner_insert"
  on storage.objects for insert with check (
    bucket_id = 'verification-ids'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "verification_ids_owner_select"
  on storage.objects for select using (
    bucket_id = 'verification-ids'
    and (
      (auth.uid() is not null and (storage.foldername(name))[1] = auth.uid()::text)
      or auth_is_staff()
    )
  );

-- Owner updates (re-upload) and deletes (account removal / wrong upload):
create policy "verification_ids_owner_update"
  on storage.objects for update using (
    bucket_id = 'verification-ids'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "verification_ids_owner_delete"
  on storage.objects for delete using (
    bucket_id = 'verification-ids'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );


-- ── 5. evidence  (any signed-in member uploads; owner/staff read) ------------
-- First path segment is the uploader's user id (see apps). Staff read all.
create policy "evidence_auth_insert"
  on storage.objects for insert with check (
    bucket_id = 'evidence'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "evidence_owner_select"
  on storage.objects for select using (
    bucket_id = 'evidence'
    and (
      (auth.uid() is not null and (storage.foldername(name))[1] = auth.uid()::text)
      or auth_is_staff()
    )
  );

create policy "evidence_owner_update"
  on storage.objects for update using (
    bucket_id = 'evidence'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "evidence_owner_delete"
  on storage.objects for delete using (
    bucket_id = 'evidence'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );


-- ============================================================================
-- VERIFY AFTER RUNNING:
--   select id, name, public from storage.buckets
--   where id in ('verification-ids','evidence');
-- Both should show public = false.
-- ============================================================================