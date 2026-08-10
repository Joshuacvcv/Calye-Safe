-- ============================================================================
-- Calye-Safe — Supabase / PostgreSQL schema
-- GPS-Enabled Community Incident Reporting & Response System
-- Barangay Calye, Santa Rosa, Laguna
--
-- HOW TO USE:
--   1. Create a Supabase project.
--   2. Open the SQL Editor (Dashboard > SQL Editor > New query).
--   3. Paste this whole file and click RUN.
--   4. (Optional) Then run db/supabase-seed.sql to load demo data.
--
-- NOTE ON AUTH:
--   The current HTML prototypes use "any email/password works" demo logins.
--   These tables reference auth.users (Supabase Auth). Wiring the apps to
--   real accounts (supabase.auth.signUp / signInWithPassword) is a later
--   step; the schema is ready for it.
-- ============================================================================


-- ============================================================================
-- 1. EXTENSIONS (optional, only if you want PostGIS geo queries)
-- ============================================================================
-- create extension if not exists postgis;

create extension if not exists "pgcrypto"; -- for gen_random_uuid()


-- ============================================================================
-- 2. ENUMS
-- ============================================================================

-- Who can use the system
create type user_role as enum (
  'resident',      -- community app
  'responder',     -- field responder / QRT app
  'staff',         -- barangay operator (web dashboard)
  'admin'          -- super user (web dashboard)
);

-- A report's lifecycle as seen in the community app timeline
create type report_status as enum (
  'pending',       -- submitted, awaiting verification
  'verified',      -- checked by an operator
  'responding',    -- a responder unit has been dispatched
  'on_site',       -- responder arrived at location
  'resolved'       -- completed with proof
);

-- Incident category (drives the map pin colors / admin groupings)
create type incident_category as enum (
  'flood',         -- flooding / clogged drains
  'hazard',        -- road hazards, broken streetlights
  'garbage',       -- uncollected garbage
  'crime',         -- crime, public disturbance, vandalism
  'fire',
  'accident',
  'other'
);

-- Severity levels used by admin dashboard (major / minor)
create type severity_level as enum ('minor', 'major');

-- Priority as shown on badges in the admin dashboard
create type priority_level as enum ('urgent', 'pending', 'responding', 'resolved');

-- A responder assignment status (matches responder app statuses)
create type job_status as enum (
  'assigned',      -- dispatched, not yet accepted
  'en_route',      -- responder heading to site
  'on_site',       -- responder at location
  'resolved',      -- completed with proof
  'escalated'      -- reported back to barangay ops
);

-- Announcement category (community app + admin)
create type ann_category as enum ('general', 'advisory', 'emergency', 'event');

-- Timeline step state
create type step_state as enum ('done', 'active', 'pending');

-- Media type attached to a report
create type media_kind as enum ('photo', 'video');


-- ============================================================================
-- 3. TABLES
-- ============================================================================

-- ── profiles ---------------------------------------------------------------
-- One row per auth.users account. Holds the display info shown on each app's
-- Profile screen (Personal Information / notification preferences / appearance).
create table if not exists profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  role          user_role not null default 'resident',
  full_name     text not null default '',
  email         text not null,
  phone         text default '',
  barangay      text not null default 'Barangay Calye',
  unit_id       text default null,             -- responder only, e.g. 'RES-014'
  shift         text default null,             -- responder only
  sector        text default null,             -- responder only (assigned sector)
  notif_prefs   jsonb not null default '{
    "reportUpdates": true,
    "emergencyAlerts": true,
    "announcements": true,
    "tips": false
  }'::jsonb,
  language      text not null default 'English',
  reduced_motion boolean not null default false,
  high_contrast  boolean not null default false,
  on_duty       boolean not null default false, -- responder duty toggle
  avatar_url    text default null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ── reports ----------------------------------------------------------------
-- Incident reports filed by residents. This is the community app's
-- "My Reports" data plus the admin dashboard's reports table.
create table if not exists reports (
  id            uuid primary key default gen_random_uuid(),
  report_no     text not null unique,          -- display id, e.g. '#BRGY-2026-0047'
  reporter_id   uuid references profiles (id) on delete set null,
  reporter_name text not null default '',      -- snapshot of who filed (works pre-auth)
  category      incident_category not null default 'other',
  type          text not null default 'Incident',  -- e.g. 'Flooding', 'Road Hazard'
  severity      severity_level not null default 'minor',
  priority      priority_level not null default 'pending',
  description   text default '',
  location      text default '',               -- street / area name
  lat           double precision not null default 0,
  lng           double precision not null default 0,
  source        text not null default 'resident', -- 'resident' or 'BRGY' (admin-entered)
  status        report_status not null default 'pending',
  announce_consent boolean not null default false, -- resident consent to publish as a public announcement
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ── report_timeline --------------------------------------------------------
-- The 5-step status timeline shown on each report's detail (community app).
-- Steps in order: Reported → Verified → Responder Dispatched → On-Site → Resolved
create table if not exists report_timeline (
  id         uuid primary key default gen_random_uuid(),
  report_id  uuid not null references reports (id) on delete cascade,
  step       int not null default 1 check (step between 1 and 5),
  label      text not null,
  note       text default '',
  happened_at text default '—',                -- human-readable 'May 16 · 10:00 AM'
  state      step_state not null default 'pending',
  created_at timestamptz not null default now(),
  unique (report_id, step)
);

-- ── report_media -----------------------------------------------------------
-- Photo / video evidence attached to a report (camera or gallery upload).
create table if not exists report_media (
  id          uuid primary key default gen_random_uuid(),
  report_id   uuid not null references reports (id) on delete cascade,
  kind        media_kind not null default 'photo',
  url         text not null,                   -- Supabase Storage path or full URL
  thumbnail   text default null,
  created_at  timestamptz not null default now()
);

-- ── responders -------------------------------------------------------------
-- Field responder units (QRT / sanitation / PNP / NDRRMC). Used by the
-- responder app's home + profile. Keep in profiles too; this holds fleet info.
create table if not exists responders (
  id         uuid primary key default gen_random_uuid(),
  unit_id    text not null unique,             -- e.g. 'RES-014'
  name       text not null,
  vehicle    text default '',                  -- 'Patrol Car', 'Rescue Truck'
  agency     text default 'Barangay Calye QRT',
  lat        double precision default null,    -- live position
  lng        double precision default null,
  updated_at timestamptz not null default now()
);

-- ── assignments (jobs) -----------------------------------------------------
-- Dispatches linking a report to a responder unit. This is the responder
-- app's "Jobs" queue and the admin dashboard's response tracking.
create table if not exists assignments (
  id             uuid primary key default gen_random_uuid(),
  report_id      uuid references reports (id) on delete set null,
  responder_id   uuid references responders (id) on delete set null,
  status         job_status not null default 'assigned',
  distance_km    double precision default null,
  eta_min        int default null,
  resolution_notes text default '',
  proof_url      text default null,            -- attached proof photo (resolve flow)
  escalated_reason text default null,          -- escalate flow reason
  created_at     timestamptz not null default now(),
  assigned_at    timestamptz,
  resolved_at    timestamptz
);

-- ── assignment_timeline ----------------------------------------------------
-- The per-job 5-step timeline shown in the responder app's job detail.
create table if not exists assignment_timeline (
  id            uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references assignments (id) on delete cascade,
  step          int not null default 1 check (step between 1 and 5),
  label         text not null,
  happened_at   text default '—',
  state         step_state not null default 'pending',
  created_at    timestamptz not null default now(),
  unique (assignment_id, step)
);

-- ── resolved_history -------------------------------------------------------
-- Denormalized resolved jobs shown on the responder app's "History" screen.
-- Kept separate so resolved assignments can be archived quickly.
create table if not exists resolved_history (
  id            uuid primary key default gen_random_uuid(),
  assignment_id uuid references assignments (id) on delete set null,
  responder_id  uuid references responders (id) on delete set null,
  report_no     text,
  type          text,
  location      text,
  resolved_at   timestamptz not null default now(),
  duration_min  int default null
);

-- ── announcements ----------------------------------------------------------
-- Barangay announcements / advisories pushed to the community app.
create table if not exists announcements (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  body       text not null,
  category   ann_category not null default 'general',
  pushed     boolean not null default false,   -- published to mobile app?
  created_by uuid references profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  published_at timestamptz
);

-- ── hotlines ---------------------------------------------------------------
-- Emergency numbers shown on the community app's Hotlines screen.
create table if not exists hotlines (
  id        uuid primary key default gen_random_uuid(),
  name      text not null,
  number    text not null,
  category  text default '',                   -- 'Barangay', 'Health', 'Police', 'Fire'
  created_at timestamptz not null default now()
);

-- ── map_incidents ----------------------------------------------------------
-- Aggregated live pins for the community map (leaflet). Can be a view over
-- reports; kept as a table so admin can override pins independently.
create table if not exists map_incidents (
  id         uuid primary key default gen_random_uuid(),
  report_id  uuid references reports (id) on delete set null,
  type       incident_category not null default 'other',
  label      text default '',
  location   text default '',
  status     report_status not null default 'pending',
  lat        double precision not null default 0,
  lng        double precision not null default 0,
  created_at timestamptz not null default now()
);


-- ============================================================================
-- 4. AUTOMATIC updated_at TRIGGER
-- ============================================================================

create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_profiles_updated on profiles;
create trigger trg_profiles_updated
  before update on profiles
  for each row execute function set_updated_at();

drop trigger if exists trg_reports_updated on reports;
create trigger trg_reports_updated
  before update on reports
  for each row execute function set_updated_at();

drop trigger if exists trg_responders_updated on responders;
create trigger trg_responders_updated
  before update on responders
  for each row execute function set_updated_at();


-- ============================================================================
-- 5. INDEXES
-- ============================================================================

create index if not exists idx_reports_status    on reports (status);
create index if not exists idx_reports_category  on reports (category);
create index if not exists idx_reports_created   on reports (created_at desc);
create index if not exists idx_reports_location  on reports (lat, lng);
create index if not exists idx_timeline_report   on report_timeline (report_id, step);
create index if not exists idx_assignments_status on assignments (status);
create index if not exists idx_assignments_resp  on assignments (responder_id, status);
create index if not exists idx_announcements_push on announcements (pushed, created_at desc);
create index if not exists idx_map_incidents_loc  on map_incidents (lat, lng);


-- ============================================================================
-- 6. ROW LEVEL SECURITY
--
-- IMPORTANT: With the current demo logins (no real Supabase Auth session),
-- the anon key CANNOT read any of these rows. RLS is set up for when real
-- auth is wired in. To view data in the prototype now you can either:
--   (a) temporarily run:  alter table ... disable row level security;
--       or
--   (b) wire the apps to supabase.auth first.
-- ============================================================================

alter table profiles          enable row level security;
alter table reports           enable row level security;
alter table report_timeline   enable row level security;
alter table report_media      enable row level security;
alter table responders        enable row level security;
alter table assignments       enable row level security;
alter table assignment_timeline enable row level security;
alter table resolved_history  enable row level security;
alter table announcements     enable row level security;
alter table hotlines          enable row level security;
alter table map_incidents     enable row level security;

-- helper: is the current user a staff/admin responder type?
create or replace function auth_is_staff()
returns boolean language sql stable as $$
  select exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role in ('staff', 'admin')
  );
$$;

create or replace function auth_is_responder()
returns boolean language sql stable as $$
  select exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role in ('responder', 'staff', 'admin')
  );
$$;

-- ---- profiles --------------------------------------------------------------
drop policy if exists "profiles_self_select" on profiles;
create policy "profiles_self_select"
  on profiles for select using (auth.uid() = id);

drop policy if exists "profiles_self_insert" on profiles;
create policy "profiles_self_insert"
  on profiles for insert with check (auth.uid() = id);

drop policy if exists "profiles_self_update" on profiles;
create policy "profiles_self_update"
  on profiles for update using (auth.uid() = id);

-- staff/admin can see everyone (to show reporter names, assign units)
drop policy if exists "profiles_staff_select" on profiles;
create policy "profiles_staff_select"
  on profiles for select using (auth_is_staff());

-- ---- reports ---------------------------------------------------------------
drop policy if exists "reports_resident_insert" on reports;
create policy "reports_resident_insert"
  on reports for insert with check (auth.uid() = reporter_id);

drop policy if exists "reports_owner_select" on reports;
create policy "reports_owner_select"
  on reports for select using (auth.uid() = reporter_id);

-- responders/staff can read every report (queue + admin dashboard)
drop policy if exists "reports_staff_select" on reports;
create policy "reports_staff_select"
  on reports for select using (auth_is_responder());

-- staff can update reports (verify, dispatch, resolve)
drop policy if exists "reports_staff_update" on reports;
create policy "reports_staff_update"
  on reports for update using (auth_is_responder());

-- ---- report_timeline -------------------------------------------------------
drop policy if exists "timeline_owner_select" on report_timeline;
create policy "timeline_owner_select"
  on report_timeline for select using (
    exists (select 1 from reports r where r.id = report_id and r.reporter_id = auth.uid())
    or auth_is_responder()
  );

drop policy if exists "timeline_staff_insert" on report_timeline;
create policy "timeline_staff_insert"
  on report_timeline for insert with check (auth_is_responder());

-- ---- report_media ----------------------------------------------------------
drop policy if exists "media_owner_select" on report_media;
create policy "media_owner_select"
  on report_media for select using (
    exists (select 1 from reports r where r.id = report_id and r.reporter_id = auth.uid())
    or auth_is_responder()
  );

drop policy if exists "media_owner_insert" on report_media;
create policy "media_owner_insert"
  on report_media for insert with check (auth.uid() = (select reporter_id from reports where id = report_id));

-- ---- responders ------------------------------------------------------------
drop policy if exists "responders_select" on responders;
create policy "responders_select"
  on responders for select using (auth_is_responder());

drop policy if exists "responders_update" on responders;
create policy "responders_update"
  on responders for update using (auth_is_staff());

-- ---- assignments -----------------------------------------------------------
drop policy if exists "assignments_staff_select" on assignments;
create policy "assignments_staff_select"
  on assignments for select using (auth_is_responder());

drop policy if exists "assignments_staff_insert" on assignments;
create policy "assignments_staff_insert"
  on assignments for insert with check (auth_is_staff());

drop policy if exists "assignments_staff_update" on assignments;
create policy "assignments_staff_update"
  on assignments for update using (auth_is_responder());

-- ---- assignment_timeline ---------------------------------------------------
drop policy if exists "at_timeline_select" on assignment_timeline;
create policy "at_timeline_select"
  on assignment_timeline for select using (auth_is_responder());

drop policy if exists "at_timeline_insert" on assignment_timeline;
create policy "at_timeline_insert"
  on assignment_timeline for insert with check (auth_is_responder());

-- ---- resolved_history ------------------------------------------------------
drop policy if exists "history_responder_select" on resolved_history;
create policy "history_responder_select"
  on resolved_history for select using (auth_is_responder());

-- ---- announcements ---------------------------------------------------------
drop policy if exists "announcements_public_select" on announcements;
create policy "announcements_public_select"
  on announcements for select using (pushed = true or auth_is_staff());

drop policy if exists "announcements_staff_insert" on announcements;
create policy "announcements_staff_insert"
  on announcements for insert with check (auth_is_staff());

drop policy if exists "announcements_staff_update" on announcements;
create policy "announcements_staff_update"
  on announcements for update using (auth_is_staff());

drop policy if exists "announcements_staff_delete" on announcements;
create policy "announcements_staff_delete"
  on announcements for delete using (auth_is_staff());

-- ---- hotlines --------------------------------------------------------------
drop policy if exists "hotlines_public_select" on hotlines;
create policy "hotlines_public_select"
  on hotlines for select using (true); -- public emergency numbers

drop policy if exists "hotlines_staff_insert" on hotlines;
create policy "hotlines_staff_insert"
  on hotlines for insert with check (auth_is_staff());

-- ---- map_incidents ---------------------------------------------------------
drop policy if exists "map_incidents_public_select" on map_incidents;
create policy "map_incidents_public_select"
  on map_incidents for select using (true); -- public map pins

drop policy if exists "map_incidents_staff_insert" on map_incidents;
create policy "map_incidents_staff_insert"
  on map_incidents for insert with check (auth_is_staff());

drop policy if exists "map_incidents_staff_update" on map_incidents;
create policy "map_incidents_staff_update"
  on map_incidents for update using (auth_is_staff());
