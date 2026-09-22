-- ============================================================================
-- Calye-Safe — Fixes for Identified Issues
-- Run AFTER supabase-schema.sql and supabase-seed.sql
-- ============================================================================


-- ============================================================================
-- 1. ENABLE POSTGIS (for geo queries: nearby incidents, responder tracking)
-- ============================================================================
create extension if not exists postgis;

-- Add geometry columns for spatial indexes
alter table reports add column if not exists geom geometry(Point, 4326);
alter table responders add column if not exists geom geometry(Point, 4326);
alter table map_incidents add column if not exists geom geometry(Point, 4326);

-- Populate geometry from lat/lng
update reports set geom = ST_SetSRID(ST_MakePoint(lng, lat), 4326) where geom is null;
update responders set geom = ST_SetSRID(ST_MakePoint(lng, lat), 4326) where geom is null and lat is not null;
update map_incidents set geom = ST_SetSRID(ST_MakePoint(lng, lat), 4326) where geom is null;

-- Spatial indexes
create index if not exists idx_reports_geom on reports using gist (geom);
create index if not exists idx_responders_geom on responders using gist (geom);
create index if not exists idx_map_incidents_geom on map_incidents using gist (geom);

-- Trigger to keep geom in sync.
-- set search_path = public is required: SECURITY DEFINER callers (e.g.
-- admin_delete_user with search_path='') otherwise inherit an empty path and
-- ST_MakePoint fails with 42883.
create or replace function update_geom_from_latlng()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.lat is not null and new.lng is not null then
    new.geom = ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326);
  end if;
  return new;
end $$;

drop trigger if exists trg_reports_geom on reports;
create trigger trg_reports_geom before insert or update on reports
  for each row execute function update_geom_from_latlng();

drop trigger if exists trg_responders_geom on responders;
create trigger trg_responders_geom before insert or update on responders
  for each row execute function update_geom_from_latlng();

drop trigger if exists trg_map_incidents_geom on map_incidents;
create trigger trg_map_incidents_geom before insert or update on map_incidents
  for each row execute function update_geom_from_latlng();


-- ============================================================================
-- 2. AUTO-SYNC report_timeline ON REPORT INSERT
-- ============================================================================
create or replace function create_report_timeline()
returns trigger language plpgsql as $$
begin
  insert into report_timeline (report_id, step, label, note, happened_at, state)
  values
    (new.id, 1, 'Report Submitted', 'Your report was received by the system.',
     to_char(new.created_at, 'Mon DD · HH:MI AM'), 'done'),
    (new.id, 2, 'Verified by Operator', 'A barangay operator has verified the incident report.', '—', 'pending'),
    (new.id, 3, 'Responder Dispatched', '—', '—', 'pending'),
    (new.id, 4, 'On-Site Response', '—', '—', 'pending'),
    (new.id, 5, 'Resolved', '—', '—', 'pending');
  return new;
end $$;

drop trigger if exists trg_create_report_timeline on reports;
create trigger trg_create_report_timeline
  after insert on reports
  for each row execute function create_report_timeline();


-- ============================================================================
-- 3. AUTO-SYNC assignment_timeline ON ASSIGNMENT INSERT
-- ============================================================================
create or replace function create_assignment_timeline()
returns trigger language plpgsql as $$
declare
  v_created_at timestamptz;
begin
  -- Step 1 "Reported" must reflect when the RESIDENT filed the report,
  -- not the dispatch moment (assignments.created_at is the dispatch time).
  select r.created_at into v_created_at from reports r where r.id = new.report_id;
  v_created_at := coalesce(v_created_at, new.created_at);

  insert into assignment_timeline (assignment_id, step, label, happened_at, state)
  values
    (new.id, 1, 'Reported', to_char(v_created_at, 'Mon DD · HH:MI AM'), 'done'),
    (new.id, 2, 'Verified & Assigned to you', to_char(coalesce(new.assigned_at, new.created_at), 'Mon DD · HH:MI AM'), 'done'),
    (new.id, 3, 'En Route', '—', 'pending'),
    (new.id, 4, 'On-Site', '—', 'pending'),
    (new.id, 5, 'Resolved', '—', 'pending');
  return new;
end $$;

drop trigger if exists trg_create_assignment_timeline on assignments;
create trigger trg_create_assignment_timeline
  after insert on assignments
  for each row execute function create_assignment_timeline();


-- ============================================================================
-- 4. AUTO-SYNC map_incidents FROM reports
-- ============================================================================
create or replace function sync_map_incidents_from_report()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    insert into map_incidents (report_id, type, label, location, status, lat, lng, geom, created_at)
    values (new.id, new.category, new.type, new.location, new.status, new.lat, new.lng,
            ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326), new.created_at);
  elsif tg_op = 'UPDATE' then
    update map_incidents
    set type = new.category,
        label = new.type,
        location = new.location,
        status = new.status,
        lat = new.lat,
        lng = new.lng,
        geom = ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326)
    where report_id = new.id;
  elsif tg_op = 'DELETE' then
    delete from map_incidents where report_id = old.id;
  end if;
  return new;
end $$;

drop trigger if exists trg_sync_map_incidents on reports;
create trigger trg_sync_map_incidents
  after insert or update or delete on reports
  for each row execute function sync_map_incidents_from_report();


-- ============================================================================
-- 5. SYNC profiles.unit_id ↔ responders.unit_id
-- ============================================================================
-- When a responder profile is updated, sync to responders table
create or replace function sync_responder_from_profile()
returns trigger language plpgsql as $$
begin
  if new.role = 'responder' and new.unit_id is not null then
    insert into responders (unit_id, name, vehicle, agency)
    values (new.unit_id, new.full_name, '', 'Barangay Calye QRT')
    on conflict (unit_id) do update set
      name = excluded.name;
  end if;
  return new;
end $$;

drop trigger if exists trg_sync_responder_from_profile on profiles;
create trigger trg_sync_responder_from_profile
  after insert or update on profiles
  for each row execute function sync_responder_from_profile();

-- When responders table is updated, sync back to profiles (optional, for admin edits)
create or replace function sync_profile_from_responder()
returns trigger language plpgsql as $$
begin
  update profiles
  set unit_id = new.unit_id,
      full_name = new.name
  where unit_id = old.unit_id or unit_id = new.unit_id;
  return new;
end $$;

drop trigger if exists trg_sync_profile_from_responder on responders;
create trigger trg_sync_profile_from_responder
  after insert or update on responders
  for each row execute function sync_profile_from_responder();


-- ============================================================================
-- 6. FIX report_media RLS - Only reporter can insert media
-- ============================================================================
drop policy if exists "media_owner_insert" on report_media;
create policy "media_owner_insert"
  on report_media for insert with check (
    auth.uid() = (select reporter_id from reports where id = report_id)
  );


-- ============================================================================
-- 7. ADD NOTIFICATIONS TABLE (for real-time alerts to all roles)
-- ============================================================================
create table if not exists notifications (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  title         text not null,
  body          text not null,
  type          text not null default 'info',  -- 'info' | 'alert' | 'update' | 'emergency'
  related_report_id uuid references reports(id) on delete set null,
  related_assignment_id uuid references assignments(id) on delete set null,
  read          boolean not null default false,
  created_at    timestamptz not null default now()
);

create index if not exists idx_notifications_user on notifications (user_id, created_at desc);
create index if not exists idx_notifications_unread on notifications (user_id, read) where read = false;

alter table notifications enable row level security;

-- Users see only their own notifications
drop policy if exists "notifications_self_select" on notifications;
create policy "notifications_self_select"
  on notifications for select using (auth.uid() = user_id);

drop policy if exists "notifications_self_update" on notifications;
create policy "notifications_self_update"
  on notifications for update using (auth.uid() = user_id);

-- Staff can insert notifications for any user
drop policy if exists "notifications_staff_insert" on notifications;
create policy "notifications_staff_insert"
  on notifications for insert with check (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('staff', 'admin'))
  );

-- Auto-create notification trigger for report status changes
-- NOTE: SECURITY DEFINER so the INSERT succeeds even when the UPDATE was made
-- with the anon key / under RLS (see supabase-notifications-rls-fix.sql).
create or replace function public.notify_report_status_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_title text;
  v_body text;
  v_type text;
begin
  if old.status is distinct from new.status then
    case new.status
      when 'verified' then
        v_title := 'Report Verified';
        v_body := 'Your report #' || new.report_no || ' has been verified by barangay staff.';
        v_type := 'update';
      when 'responding' then
        v_title := 'Responder Dispatched';
        v_body := 'A responder unit is on the way to your reported location.';
        v_type := 'update';
      when 'on_site' then
        v_title := 'Responder On-Site';
        v_body := 'The responder has arrived at the location.';
        v_type := 'update';
      when 'resolved' then
        v_title := 'Report Resolved';
        v_body := 'Your report #' || new.report_no || ' has been resolved.';
        v_type := 'update';
      else
        v_title := 'Report Status Updated';
        v_body := 'Your report #' || new.report_no || ' status changed to ' || new.status || '.';
        v_type := 'update';
    end case;

    if new.reporter_id is not null then
      insert into public.notifications (user_id, title, body, type, related_report_id)
      values (new.reporter_id, v_title, v_body, v_type, new.id);
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_notify_report_status on reports;
create trigger trg_notify_report_status
  after update on reports
  for each row execute function public.notify_report_status_change();

-- Auto-create notification for new assignment (to responder)
create or replace function public.notify_new_assignment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_profile_id uuid;
begin
  if tg_op = 'INSERT' then
    select id into v_profile_id from public.profiles where unit_id = (
      select unit_id from public.responders where id = new.responder_id
    );

    if v_profile_id is not null then
      insert into public.notifications (user_id, title, body, type, related_report_id, related_assignment_id)
      select v_profile_id,
             'New Assignment',
             'You have been assigned to report #' || r.report_no || ': ' || r.type,
             'alert',
             r.id,
             new.id
      from public.reports r where r.id = new.report_id;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_notify_new_assignment on assignments;
create trigger trg_notify_new_assignment
  after insert on assignments
  for each row execute function public.notify_new_assignment();


-- ============================================================================
-- 8. ADDITIONAL USEFUL INDEXES
-- ============================================================================
create index if not exists idx_assignments_report on assignments(report_id);
create index if not exists idx_reports_reporter_status on reports(reporter_id, status);
create index if not exists idx_assignments_responder_status on assignments(responder_id, status);
create index if not exists idx_report_timeline_report_step on report_timeline(report_id, step);
create index if not exists idx_assignment_timeline_assignment_step on assignment_timeline(assignment_id, step);


-- ============================================================================
-- 9. HELPER FUNCTIONS FOR REAL-TIME QUERIES
-- ============================================================================

-- Get nearby reports (within radius meters)
create or replace function get_nearby_reports(p_lat double precision, p_lng double precision, p_radius_meters int default 1000)
returns table (
  id uuid,
  report_no text,
  type text,
  category incident_category,
  severity severity_level,
  status report_status,
  location text,
  distance_meters double precision,
  created_at timestamptz
) language sql stable as $$
  select r.id, r.report_no, r.type, r.category, r.severity, r.status, r.location,
         ST_Distance(r.geom, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography) as distance_meters,
         r.created_at
  from reports r
  where r.geom is not null
    and ST_DWithin(r.geom, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography, p_radius_meters)
  order by distance_meters
  limit 50;
$$;

-- Get available responders near location
create or replace function get_nearby_responders(p_lat double precision, p_lng double precision, p_radius_meters int default 5000)
returns table (
  id uuid,
  unit_id text,
  name text,
  vehicle text,
  agency text,
  distance_meters double precision,
  on_duty boolean
) language sql stable as $$
  select res.id, res.unit_id, res.name, res.vehicle, res.agency,
         ST_Distance(res.geom, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography) as distance_meters,
         p.on_duty
  from responders res
  join profiles p on p.unit_id = res.unit_id
  where res.geom is not null
    and p.role = 'responder'
    and p.on_duty = true
    and ST_DWithin(res.geom, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography, p_radius_meters)
  order by distance_meters;
$$;

-- Get unread notification count for current user
create or replace function get_unread_notification_count()
returns int language sql stable as $$
  select count(*) from notifications where user_id = auth.uid() and read = false;
$$;

-- Mark all notifications as read
create or replace function mark_all_notifications_read()
returns void language sql as $$
  update notifications set read = true where user_id = auth.uid() and read = false;
$$;


-- ============================================================================
-- 10. REALTIME PUBLICATION (enable for Supabase Realtime)
-- ============================================================================
-- Run these in Supabase Dashboard > Database > Replication
-- Or via SQL:
-- alter publication supabase_realtime add table reports;
-- alter publication supabase_realtime add table assignments;
-- alter publication supabase_realtime add table report_timeline;
-- alter publication supabase_realtime add table assignment_timeline;
-- alter publication supabase_realtime add table notifications;
-- alter publication supabase_realtime add table responders;
-- alter publication supabase_realtime add table announcements;
-- alter publication supabase_realtime add table map_incidents;

-- Note: For Supabase, you typically enable realtime in the dashboard.
-- The above are reference commands. In dashboard: Database > Replication > Enable for each table.


-- ============================================================================
-- 11. UPDATED_AT TRIGGERS FOR NEW TABLES
-- ============================================================================
-- NOTE: notifications has no `updated_at` column, so a set_updated_at trigger
-- on it would error ("record new has no field updated_at") whenever the table
-- is touched (e.g. ON DELETE SET NULL from reports). Drop it if present.
drop trigger if exists trg_notifications_updated on notifications;


-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================
-- Test triggers work:
-- insert into reports (report_no, reporter_name, category, type, severity, priority, description, location, lat, lng, source)
-- values ('#TEST-001', 'Test User', 'flood', 'Flooding', 'minor', 'pending', 'Test', 'Test Location', 14.31, 121.11, 'resident');
--
-- Check: select * from report_timeline where report_id = (select id from reports where report_no = '#TEST-001');
-- Check: select * from map_incidents where report_id = (select id from reports where report_no = '#TEST-001');
-- Check: select * from notifications where related_report_id = (select id from reports where report_no = '#TEST-001');