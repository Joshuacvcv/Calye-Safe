-- ============================================================================
-- CALYE-SAFE — Sign-in verification / account approval migration
--
-- Adds the residency & employment verification workflow:
--   1. Any new sign-up is locked (verification_status = 'pending').
--   2. The user uploads a valid ID photo (Supabase Storage bucket
--      'verification-ids') and fills in their details.
--   3. A barangay staff/admin reviews the ID in the admin "Verify Users"
--      queue and Approves or Rejects (with a reason).
--   4. Only approved accounts can use the apps (reports / jobs).
--
-- Safe to re-run. Assumes supabase-schema.sql already ran.
-- NOTE: RLS is OFF for demo; the app-level gate still blocks unapproved users.
-- ============================================================================


-- ── 1. ENUMS ────────────────────────────────────────────────────────────────
do $$ begin
    create type verification_status as enum (
      'pending',    -- waiting for barangay review
      'approved',   -- residency/employment verified by staff
      'rejected'    -- failed review; user can re-upload and resubmit
    );
exception when duplicate_object then null; end $$;


-- ── 2. PROFILES: add verification columns ───────────────────────────────────
alter table profiles
  add column if not exists verification_status verification_status not null default 'pending',
  add column if not exists id_doc_url        text default null,   -- public URL of the uploaded ID photo
  add column if not exists id_type           text default null,   -- e.g. 'National ID', 'Driver's License'
  add column if not exists employment_info   text default null,   -- responder only: unit / agency affiliation
  add column if not exists address           text default '',     -- street / purok / zone the user states
  add column if not exists verified_at       timestamptz,
  add column if not exists verified_by       uuid references profiles (id) on delete set null;


-- ── 3. VERIFICATION REQUESTS (audit trail, one row per submission) ──────────
create table if not exists verification_requests (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references profiles (id) on delete cascade,
  role            user_role not null default 'resident',
  full_name       text not null default '',
  email           text not null,
  address         text not null default '',
  employment_info text default null,          -- responder only
  id_doc_url      text not null,              -- uploaded ID photo URL
  id_type         text default '',
  status          verification_status not null default 'pending',
  review_note     text default '',            -- reason shown to the user when rejected
  submitted_at    timestamptz not null default now(),
  reviewed_at     timestamptz,
  reviewed_by     uuid references profiles (id) on delete set null,
  created_at      timestamptz not null default now()
);

create index if not exists idx_verif_requests_status on verification_requests (status, submitted_at desc);
create index if not exists idx_verif_requests_user on verification_requests (user_id);


-- ── 4. AUTO-CREATE PROFILE ON SIGN-UP ───────────────────────────────────────
-- Every Supabase Auth sign-up immediately gets a pending profile row.
-- The profile's verification_status is set from the signing-up role via
-- auth.jwt() claims (see supabase-auth.js: it calls signUp with user_metadata
-- { role: 'resident' | 'responder' }).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email, full_name, role, verification_status)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    case when (new.raw_user_meta_data->>'role') = 'responder' then 'responder'::public.user_role
         else 'resident'::public.user_role end,
    'pending'::public.verification_status
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ── 5. HELPER: approved user check ──────────────────────────────────────────
-- Replaces nothing today (RLS off), but ready for when RLS is re-enabled so
-- unapproved accounts can't touch reports / assignments / announcements.
create or replace function auth_is_approved()
returns boolean language sql stable set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.verification_status = 'approved'
  );
$$;


-- ── 6. STORAGE BUCKET + POLICIES ────────────────────────────────────────────
-- Bucket: verification-ids  (ID photos for sign-up review)
-- Demo: anyone can upload / read so the prototype works with the anon key.
-- LOCKDOWN for production: insert = auth.uid() = owner only, read = owner or
-- staff, and objects removed on account delete (see commented section at end).
insert into storage.buckets (id, name, public)
values ('verification-ids', 'verification-ids', true)
on conflict (id) do nothing;

drop policy if exists "verification_ids_anon_insert" on storage.objects;
create policy "verification_ids_anon_insert"
  on storage.objects for insert
  with check (bucket_id = 'verification-ids');

drop policy if exists "verification_ids_anon_select" on storage.objects;
create policy "verification_ids_anon_select"
  on storage.objects for select
  using (bucket_id = 'verification-ids');

drop policy if exists "verification_ids_anon_update" on storage.objects;
create policy "verification_ids_anon_update"
  on storage.objects for update
  using (bucket_id = 'verification-ids');

drop policy if exists "verification_ids_anon_delete" on storage.objects;
create policy "verification_ids_anon_delete"
  on storage.objects for delete
  using (bucket_id = 'verification-ids');


-- ── 7. RLS on verification_requests (prepared for re-enabling) ──────────────
alter table verification_requests enable row level security;

drop policy if exists "verif_req_owner_select" on verification_requests;
create policy "verif_req_owner_select"
  on verification_requests for select using (auth.uid() = user_id);

drop policy if exists "verif_req_owner_insert" on verification_requests;
create policy "verif_req_owner_insert"
  on verification_requests for insert with check (auth.uid() = user_id);

drop policy if exists "verif_req_staff_select" on verification_requests;
create policy "verif_req_staff_select"
  on verification_requests for select using (auth_is_staff());

drop policy if exists "verif_req_staff_update" on verification_requests;
create policy "verif_req_staff_update"
  on verification_requests for update using (auth_is_staff());


-- ============================================================================
-- PRODUCTION LOCKDOWN (replace section 6 when auth is enforced):
--
--   drop policy if exists "verification_ids_anon_insert" on storage.objects;
--   drop policy if exists "verification_ids_anon_select" on storage.objects;
--   drop policy if exists "verification_ids_anon_update" on storage.objects;
--   drop policy if exists "verification_ids_anon_delete" on storage.objects;
--
--   create policy "verification_ids_owner_insert"
--     on storage.objects for insert with check (
--       bucket_id = 'verification-ids'
--       and auth.uid() is not null
--       and (storage.foldername(name))[1] = auth.uid()::text
--     );
--
--   create policy "verification_ids_owner_read"
--     on storage.objects for select using (
--       bucket_id = 'verification-ids'
--       and (auth.uid() is not null
--            and (storage.foldername(name))[1] = auth.uid()::text
--            or auth_is_staff())
--     );
-- ============================================================================
