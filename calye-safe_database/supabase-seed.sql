-- ============================================================================
-- Calye-Safe — Seed data (demo records matching the HTML prototypes)
-- Run AFTER db/supabase-schema.sql (i.e. supabase-seed.sql)
--
-- NOTE:
--   * reporter_id / created_by columns reference profiles (auth.users). The
--     demo HTML apps use fake logins, so these are left NULL and we store the
--     display name in reporter_name instead.
--   * The responses table (community app) maps to `responders`.
--   * report_no strings like '#BRGY-2026-0047' match the prototypes exactly.
-- ============================================================================


-- ============================================================================
-- 1. RESPONDERS (field units shown on the responder app + community live view)
-- ============================================================================
insert into responders (unit_id, name, vehicle, agency) values
  ('RES-014', 'Mark Anthony Reyes',     'Patrol Vehicle', 'Barangay Calye QRT'),
  ('RES-015', 'Andrea Villanueva',      'Ambulance',      'Barangay Health Unit'),
  ('RES-016', 'Ramon Ocampo',           'Rescue Truck',   'Barangay Calye QRT'),
  ('PNP-12',  'PNP Mobile Unit 12',     'Patrol Car',     'Santa Rosa PNP'),
  ('NDR-03',  'NDRRMC Rescue Team 3',   'Rescue Truck',   'NDRRMC Santa Rosa');


-- ============================================================================
-- 2. REPORTS  (community app "My Reports" + admin dashboard)
--    status values: pending / verified / responding / on_site / resolved
-- ============================================================================
insert into reports (report_no, reporter_name, category, type, severity, priority,
                     description, location, lat, lng, source, status, created_at)
values
  -- Active report with a live responder (community app example #BRGY-2026-0038)
  ('#BRGY-2026-0038', 'Juan Dela Cruz', 'accident', 'Road Accident',
   'major', 'responding',
   'Road accident near the covered court entrance. Traffic backed up in both lanes.',
   'Division Road', 14.3122, 121.1114, 'resident', 'responding',
   now() - interval '3 days'),

  ('#BRGY-2026-0047', 'Juan Dela Cruz', 'flood', 'Flooding',
   'major', 'responding',
   'Ankle-deep floodwater near the covered court entrance. Residents are unable to pass safely on foot.',
   'Mercado Village', 14.2989, 121.1163, 'resident', 'responding',
   now() - interval '1 day'),

  ('#BRGY-2026-0046', 'Ana Santos', 'hazard', 'Road Hazard',
   'minor', 'urgent',
   'Large pothole exposed after yesterday''s rain. Motorcycles swerving into the oncoming lane to avoid it.',
   'Division Road', 14.3097, 121.1210, 'resident', 'pending',
   now() - interval '1 day'),

  ('#BRGY-2026-0045', 'Carlo Mendoza', 'crime', 'Vandalism',
   'minor', 'pending',
   'Graffiti spray-painted on the community hall wall overnight.',
   'Calye Street', 14.3105, 121.1092, 'resident', 'verified',
   now() - interval '1 day'),

  ('#BRGY-2026-0044', 'Liza Ramos', 'garbage', 'Uncollected Garbage',
   'minor', 'responding',
   'Uncollected garbage bags piling up near the corner sari-sari store, attracting stray animals.',
   'Bankley Area', 14.3090, 121.1128, 'resident', 'responding',
   now() - interval '1 day'),

  ('#BRGY-2026-0043', 'Rico Fernandez', 'hazard', 'Broken Streetlight',
   'minor', 'responding',
   'Streetlight along the park pathway has been flickering and is now completely out; area is unlit at night.',
   'Calye Park', 14.3135, 121.1078, 'resident', 'on_site',
   now() - interval '1 day'),

  -- Resolved examples
  ('#BRGY-2026-0042', 'Diana Cruz', 'flood', 'Flooding',
   'major', 'resolved',
   'Creek overflowed after heavy rain. Water receded by afternoon.',
   'Calye Creek', 14.3110, 121.1130, 'resident', 'resolved',
   now() - interval '2 days'),

  ('#BRGY-2026-0041', 'Jun Reyes', 'crime', 'Public Disturbance',
   'minor', 'resolved',
   'Loud altercation near the basketball court. Resolved by barangay tanod.',
   'Barangay Hall', 14.3128, 121.1109, 'resident', 'resolved',
   now() - interval '3 days'),

  ('#BRGY-2026-0040', 'Maria Lopez', 'flood', 'Clogged Drains',
   'minor', 'resolved',
   'Drainage canal clogged with debris; water backing up on Mercado St.',
   'Mercado St.', 14.3148, 121.1140, 'resident', 'resolved',
   now() - interval '4 days'),

  ('#BRGY-2026-0035', 'Ana Santos', 'garbage', 'Uncollected Garbage',
   'minor', 'resolved',
   'Garbage not collected on schedule; bags left on the curb for three days.',
   'Bankley', 14.3092, 121.1126, 'resident', 'resolved',
   now() - interval '27 days');


-- ============================================================================
-- 3. REPORT TIMELINE (5-step timeline per report)
--    steps: 1 Reported, 2 Verified, 3 Responder Dispatched, 4 On-Site, 5 Resolved
-- ============================================================================
insert into report_timeline (report_id, step, label, note, happened_at, state)
select r.id, t.step, t.label, t.note, t.happened_at, t.state::step_state
from reports r
cross join (values
  (1, 'Report Submitted', 'Your report was received by the system.', 'May 16 · 10:00 AM', 'done'),
  (2, 'Verified by Operator', 'A barangay operator has verified the incident report.', 'May 16 · 10:05 AM', 'done'),
  (3, 'Responder Dispatched', 'PNP unit dispatched. ETA: 10 minutes.', 'May 16 · 10:12 AM', 'active'),
  (4, 'On-Site Response', 'Waiting for responder to arrive at location.', '—', 'pending'),
  (5, 'Resolved', 'Awaiting resolution confirmation.', '—', 'pending')
) as t(step, label, note, happened_at, state)
where r.report_no = '#BRGY-2026-0038';

insert into report_timeline (report_id, step, label, note, happened_at, state)
select r.id, t.step, t.label, t.note, t.happened_at, t.state::step_state
from reports r
cross join (values
  (1, 'Report Submitted', 'Flood report received.', 'Today · 10:14 AM', 'done'),
  (2, 'Verified & Assigned', 'Responder unit assigned by operator.', 'Today · 10:18 AM', 'done'),
  (3, 'En Route', 'Unit heading to location. ETA: 6 minutes.', 'Today · 10:20 AM', 'active'),
  (4, 'On-Site', '—', '—', 'pending'),
  (5, 'Resolved', '—', '—', 'pending')
) as t(step, label, note, happened_at, state)
where r.report_no = '#BRGY-2026-0047';

insert into report_timeline (report_id, step, label, note, happened_at, state)
select r.id, t.step, t.label, t.note, t.happened_at, t.state::step_state
from reports r
cross join (values
  (1, 'Report Submitted', 'Report received.', 'Today · 9:50 AM', 'done'),
  (2, 'Verified by Operator', 'Hazard confirmed near school.', 'Today · 9:58 AM', 'done'),
  (3, 'Responder Dispatched', '—', '—', 'pending'),
  (4, 'On-Site Response', '—', '—', 'pending'),
  (5, 'Resolved', '—', '—', 'pending')
) as t(step, label, note, happened_at, state)
where r.report_no = '#BRGY-2026-0046';

insert into report_timeline (report_id, step, label, note, happened_at, state)
select r.id, t.step, t.label, t.note, t.happened_at, t.state::step_state
from reports r
cross join (values
  (1, 'Report Submitted', 'Vandalism report received.', 'Today · 9:02 AM', 'done'),
  (2, 'Verified by Operator', 'Confirmed by CCTV footage.', 'Today · 9:20 AM', 'done'),
  (3, 'Responder Dispatched', '—', '—', 'pending'),
  (4, 'On-Site Response', '—', '—', 'pending'),
  (5, 'Resolved', '—', '—', 'pending')
) as t(step, label, note, happened_at, state)
where r.report_no = '#BRGY-2026-0045';

insert into report_timeline (report_id, step, label, note, happened_at, state)
select r.id, t.step, t.label, t.note, t.happened_at, t.state::step_state
from reports r
cross join (values
  (1, 'Report Submitted', 'Garbage report received.', 'Today · 8:30 AM', 'done'),
  (2, 'Verified & Assigned', 'Sanitation team assigned.', 'Today · 8:36 AM', 'done'),
  (3, 'En Route', 'Team heading to location.', 'Today · 9:02 AM', 'done'),
  (4, 'On-Site', '—', '—', 'active'),
  (5, 'Resolved', '—', '—', 'pending')
) as t(step, label, note, happened_at, state)
where r.report_no = '#BRGY-2026-0044';

insert into report_timeline (report_id, step, label, note, happened_at, state)
select r.id, t.step, t.label, t.note, t.happened_at, t.state::step_state
from reports r
cross join (values
  (1, 'Report Submitted', 'Streetlight report received.', 'Yesterday · 6:40 PM', 'done'),
  (2, 'Verified & Assigned', 'Maintenance unit assigned.', 'Yesterday · 7:05 PM', 'done'),
  (3, 'En Route', 'Unit en route.', 'Today · 8:10 AM', 'done'),
  (4, 'On-Site', 'Unit working on-site.', 'Today · 8:22 AM', 'done'),
  (5, 'Resolved', '—', '—', 'pending')
) as t(step, label, note, happened_at, state)
where r.report_no = '#BRGY-2026-0043';

-- Resolved reports get full timelines
insert into report_timeline (report_id, step, label, note, happened_at, state)
select r.id, t.step, t.label, t.note, t.happened_at, t.state::step_state
from reports r
cross join (values
  (1, 'Report Submitted', 'Your report was received.', 'May 4 · 6:30 AM', 'done'),
  (2, 'Verified by Operator', 'Confirmed by barangay sanitation.', 'May 4 · 7:00 AM', 'done'),
  (3, 'Responder Dispatched', 'Sanitation team assigned.', 'May 4 · 8:00 AM', 'done'),
  (4, 'On-Site Response', 'Garbage collected and area cleaned.', 'May 4 · 10:30 AM', 'done'),
  (5, 'Resolved', 'Issue fully resolved. Thank you for reporting!', 'May 4 · 11:00 AM', 'done')
) as t(step, label, note, happened_at, state)
where r.report_no = '#BRGY-2026-0035';

insert into report_timeline (report_id, step, label, note, happened_at, state)
select r.id, t.step, t.label, t.note, t.happened_at, t.state::step_state
from reports r
cross join (values
  (1, 'Report Submitted', 'Flood report received.', 'May 18 · 9:00 AM', 'done'),
  (2, 'Verified by Operator', 'Confirmed: flooding in low-lying areas.', 'May 18 · 9:20 AM', 'done'),
  (3, 'Responder Dispatched', 'NDRRMC team en route.', 'May 18 · 9:45 AM', 'done'),
  (4, 'On-Site Response', 'Pumps deployed; water receding.', 'May 18 · 11:00 AM', 'done'),
  (5, 'Resolved', 'Issue fully resolved.', 'May 18 · 2:30 PM', 'done')
) as t(step, label, note, happened_at, state)
where r.report_no = '#BRGY-2026-0042';


-- ============================================================================
-- 4. ASSIGNMENTS (responder app job queue) + assignment timelines
-- ============================================================================
insert into assignments (report_id, responder_id, status, distance_km, eta_min,
                         resolution_notes, created_at, assigned_at)
select r.id, res.id, 'assigned', 1.2, 6, null, r.created_at, r.created_at + interval '4 minutes'
from reports r
join responders res on res.unit_id = 'RES-014'
where r.report_no = '#BRGY-2026-0047';

insert into assignments (report_id, responder_id, status, distance_km, eta_min,
                         resolution_notes, created_at, assigned_at)
select r.id, res.id, 'assigned', 2.4, 9, null, r.created_at, r.created_at + interval '8 minutes'
from reports r
join responders res on res.unit_id = 'RES-014'
where r.report_no = '#BRGY-2026-0046';

insert into assignments (report_id, responder_id, status, distance_km, eta_min,
                         resolution_notes, created_at, assigned_at)
select r.id, res.id, 'en_route', 0.6, 3, null, r.created_at, r.created_at + interval '6 minutes'
from reports r
join responders res on res.unit_id = 'RES-014'
where r.report_no = '#BRGY-2026-0044';

insert into assignments (report_id, responder_id, status, distance_km, eta_min,
                         resolution_notes, created_at, assigned_at)
select r.id, res.id, 'on_site', 0.9, 4, 'Streetlight inspected; replacing bulb.', r.created_at, r.created_at + interval '25 minutes'
from reports r
join responders res on res.unit_id = 'RES-014'
where r.report_no = '#BRGY-2026-0043';

insert into assignments (report_id, responder_id, status, distance_km, eta_min,
                         resolution_notes, created_at, assigned_at, resolved_at)
select r.id, res.id, 'resolved', 1.1, 5, 'Creek overflow cleared; drains unclogged.', r.created_at, r.created_at + interval '30 minutes', r.created_at + interval '5 hours'
from reports r
join responders res on res.unit_id = 'NDR-03'
where r.report_no = '#BRGY-2026-0042';

insert into assignments (report_id, responder_id, status, distance_km, eta_min,
                         resolution_notes, created_at, assigned_at, resolved_at)
select r.id, res.id, 'resolved', 0.4, 2, 'Garbage collected and area cleaned.', r.created_at, r.created_at + interval '30 minutes', r.created_at + interval '2 hours'
from reports r
join responders res on res.unit_id = 'RES-014'
where r.report_no = '#BRGY-2026-0035';

-- Assignment timelines for the 6 assignments above (stepwise)
insert into assignment_timeline (assignment_id, step, label, happened_at, state)
select a.id, t.step, t.label, t.happened_at, t.state::step_state
from assignments a
join reports r on r.id = a.report_id
cross join (values
  (1, 'Reported', '10:14 AM', 'done'),
  (2, 'Verified & Assigned to you', '10:18 AM', 'done'),
  (3, 'En Route', '—', 'pending'),
  (4, 'On-Site', '—', 'pending'),
  (5, 'Resolved', '—', 'pending')
) as t(step, label, happened_at, state)
where r.report_no = '#BRGY-2026-0047';

insert into assignment_timeline (assignment_id, step, label, happened_at, state)
select a.id, t.step, t.label, t.happened_at, t.state::step_state
from assignments a
join reports r on r.id = a.report_id
cross join (values
  (1, 'Reported', '9:50 AM', 'done'),
  (2, 'Verified & Assigned to you', '9:58 AM', 'done'),
  (3, 'En Route', '—', 'pending'),
  (4, 'On-Site', '—', 'pending'),
  (5, 'Resolved', '—', 'pending')
) as t(step, label, happened_at, state)
where r.report_no = '#BRGY-2026-0046';

insert into assignment_timeline (assignment_id, step, label, happened_at, state)
select a.id, t.step, t.label, t.happened_at, t.state::step_state
from assignments a
join reports r on r.id = a.report_id
cross join (values
  (1, 'Reported', '8:30 AM', 'done'),
  (2, 'Verified & Assigned to you', '8:36 AM', 'done'),
  (3, 'En Route', '9:02 AM', 'done'),
  (4, 'On-Site', '—', 'pending'),
  (5, 'Resolved', '—', 'pending')
) as t(step, label, happened_at, state)
where r.report_no = '#BRGY-2026-0044';

insert into assignment_timeline (assignment_id, step, label, happened_at, state)
select a.id, t.step, t.label, t.happened_at, t.state::step_state
from assignments a
join reports r on r.id = a.report_id
cross join (values
  (1, 'Reported', 'Yesterday · 6:40 PM', 'done'),
  (2, 'Verified & Assigned to you', 'Yesterday · 7:05 PM', 'done'),
  (3, 'En Route', 'Today · 8:10 AM', 'done'),
  (4, 'On-Site', 'Today · 8:22 AM', 'active'),
  (5, 'Resolved', '—', 'pending')
) as t(step, label, happened_at, state)
where r.report_no = '#BRGY-2026-0043';

insert into assignment_timeline (assignment_id, step, label, happened_at, state)
select a.id, t.step, t.label, t.happened_at, t.state::step_state
from assignments a
join reports r on r.id = a.report_id
cross join (values
  (1, 'Reported', 'Yesterday · 9:00 AM', 'done'),
  (2, 'Verified & Assigned to you', 'Yesterday · 9:30 AM', 'done'),
  (3, 'En Route', 'Yesterday · 10:00 AM', 'done'),
  (4, 'On-Site', 'Yesterday · 10:45 AM', 'done'),
  (5, 'Resolved', 'Yesterday · 2:30 PM', 'done')
) as t(step, label, happened_at, state)
where r.report_no = '#BRGY-2026-0042';

insert into assignment_timeline (assignment_id, step, label, happened_at, state)
select a.id, t.step, t.label, t.happened_at, t.state::step_state
from assignments a
join reports r on r.id = a.report_id
cross join (values
  (1, 'Reported', 'May 4 · 6:30 AM', 'done'),
  (2, 'Verified & Assigned to you', 'May 4 · 7:00 AM', 'done'),
  (3, 'En Route', 'May 4 · 8:00 AM', 'done'),
  (4, 'On-Site', 'May 4 · 10:30 AM', 'done'),
  (5, 'Resolved', 'May 4 · 11:00 AM', 'done')
) as t(step, label, happened_at, state)
where r.report_no = '#BRGY-2026-0035';


-- ============================================================================
-- 5. RESOLVED HISTORY (responder app "History" screen)
-- ============================================================================
insert into resolved_history (assignment_id, responder_id, report_no, type, location,
                              resolved_at, duration_min)
select a.id, a.responder_id, r.report_no, r.type, r.location, a.resolved_at, 300
from assignments a
join reports r on r.id = a.report_id
where r.report_no = '#BRGY-2026-0042';

insert into resolved_history (assignment_id, responder_id, report_no, type, location,
                              resolved_at, duration_min)
select a.id, a.responder_id, r.report_no, r.type, r.location, a.resolved_at, 120
from assignments a
join reports r on r.id = a.report_id
where r.report_no = '#BRGY-2026-0035';


-- ============================================================================
-- 6. ANNOUNCEMENTS
-- ============================================================================
insert into announcements (title, body, category, pushed, created_at, published_at) values
  ('Flood Advisory — Mercado Village',
   'Residents near Mercado Village and low-lying areas are advised to prepare for possible flooding due to continuous rainfall. Please secure valuables and move to higher ground if water levels rise.',
   'advisory', true, now() - interval '2 days', now() - interval '2 days'),

  ('Barangay Assembly — May 25',
   'All households are requested to send at least one representative to the Barangay Assembly on May 25, 8:00 AM at the Barangay Hall for the quarterly community briefing.',
   'event', true, now() - interval '4 days', now() - interval '4 days'),

  ('Garbage Collection Schedule Update',
   'Garbage collection for Purok 3 and Purok 4 will move from Tuesdays/Fridays to Mondays/Thursdays starting next week. Please prepare your garbage accordingly.',
   'general', false, now() - interval '7 days', null);


-- ============================================================================
-- 7. HOTLINES (community app Emergency Hotlines screen)
-- ============================================================================
insert into hotlines (name, number, category) values
  ('Barangay Hotline',     '0900-000-0001', 'Barangay'),
  ('Health Center / BHW',  '0900-000-0002', 'Health'),
  ('PNP / Police Station', '0900-000-0003', 'Police'),
  ('BFP / Fire Station',   '0900-000-0004', 'Fire'),
  ('NDRRMC Rescue',        '0900-000-0005', 'Rescue');


-- ============================================================================
-- 8. MAP INCIDENTS (community app public incident map pins)
-- ============================================================================
insert into map_incidents (report_id, type, label, location, status, lat, lng, created_at)
select r.id, r.category, r.type, r.location, r.status, r.lat, r.lng, r.created_at
from reports r
where r.report_no in ('#BRGY-2026-0047','#BRGY-2026-0046','#BRGY-2026-0045',
                      '#BRGY-2026-0044','#BRGY-2026-0043');

-- Extra pins seen on the prototype map (no linked report)
insert into map_incidents (report_id, type, label, location, status, lat, lng) values
  (null, 'crime',       'Public Disturbance', 'Phase 2',   'verified',   14.3075, 121.1100),
  (null, 'hazard',      'Broken Streetlight', 'Sitio A',   'resolved',   14.3135, 121.1078),
  (null, 'crime',       'Crime',              'Brgy. Calye','verified',  14.3162, 121.1098),
  (null, 'fire',        'Fire',               'Sitio B',   'responding', 14.3096, 121.1160);
