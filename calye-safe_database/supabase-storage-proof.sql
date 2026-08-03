-- =============================================================================
-- RESOLUTION PROOF STORAGE
-- Creates a public 'evidence' bucket where responders upload resolution proof
-- photos, replacing base64 data URLs in assignments.proof_url with a public URL.
--
-- Run once in the Supabase SQL Editor AFTER supabase-resolution-evidence.sql.
-- =============================================================================

-- 1. Create the bucket (public = anyone with the URL can read)
insert into storage.buckets (id, name, public)
values ('evidence', 'evidence', true)
on conflict (id) do nothing;

-- 2. Allow authenticated responders/staff/admin to upload proof photos
drop policy if exists "evidence_proof_upload" on storage.objects;
create policy "evidence_proof_upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'evidence');

-- 3. Public read of uploaded proof photos (public bucket)
drop policy if exists "evidence_public_read" on storage.objects;
create policy "evidence_public_read"
  on storage.objects for select using (bucket_id = 'evidence');
