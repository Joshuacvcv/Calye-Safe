-- ============================================================================
-- Calye-Safe — MOCK performer data (TEST DATA ONLY)
--
-- Purpose: fill the Responder Performance tab so its charts, rates and
-- timings can be reviewed with realistic numbers.
--
-- Creates 12 reports (3 per unit: 2 resolved + 1 en-route) spread over the
-- last 5 days, linked to the CURRENT unit ids by unit_id lookup (safe
-- against UUID changes). Timelines + map pins follow via DB triggers.
--
-- HOW TO USE: paste the whole file into the Supabase SQL Editor and RUN.
--   Prerequisites: responders RES-001..004 present, subtype column applied.
--   View in: admin → Responder Performance, period "All time" / "Last 7 days".
--
-- CLEANUP (run when done checking):
--   create temp table mock_rep_ids as
--     select id from reports where report_no like '#MOCK-%';
--   delete from map_incidents where report_id in (select id from mock_rep_ids);
--   delete from assignment_timeline where assignment_id in
--     (select id from assignments where report_id in (select id from mock_rep_ids));
--   delete from assignments where report_id in (select id from mock_rep_ids);
--   delete from reports where id in (select id from mock_rep_ids);
--   (report_timeline rows cascade automatically.)
-- ============================================================================

insert into reports
  (report_no, reporter_name, category, type, subtype, severity, priority,
   description, location, lat, lng, source, status, announce_consent, created_at)
values
-- ── RES-001 jobs ────────────────────────────────────────────────────────────
('#MOCK-2026-01', 'Liza Ramos', 'flood', 'Natural Disasters & Flooding',
 'Flash floods / rising floodwater (baha)', 'major', 'urgent',
 'Ankle-deep floodwater on our street after one hour of heavy rain.',
 'Mercado Village', 14.2989, 121.1163, 'resident', 'resolved', false, now() - interval '2 days'),
('#MOCK-2026-02', 'Ramon Cruz', 'garbage', 'Garbage & Sanitation',
 'Uncollected garbage / missed collection schedule', 'minor', 'pending',
 'Garbage truck skipped our street twice. Bags are piling up and smell bad.',
 'Phase 2', 14.3075, 121.1100, 'resident', 'resolved', false, now() - interval '4 days'),
('#MOCK-2026-03', 'Ana Torres', 'hazard', 'Road & Infrastructure Hazards',
 'Potholes and road deterioration (malalim na butas sa kalsada)', 'minor', 'pending',
 'Deep pothole in the middle of the lane gave two motorcycles flat tires this week.',
 'Calye Street', 14.3105, 121.1092, 'resident', 'responding', false, now() - interval '1 day'),

-- ── RES-002 jobs ────────────────────────────────────────────────────────────
('#MOCK-2026-04', 'Mark Villanueva', 'fire', 'Fire (Sunog)',
 'Grass fires / cogon fires near communities', 'major', 'pending',
 'Cogon grass burning at the vacant lot beside the chapel. Smoke reaching houses.',
 'Purok 3', 14.3096, 121.1160, 'resident', 'resolved', false, now() - interval '2 days'),
('#MOCK-2026-05', 'Jenny Lim', 'crime', 'Crime & Public Safety',
 'Theft (vehicle, livestock, valuables)', 'major', 'pending',
 'Bicycle stolen from outside the sari-sari store yesterday afternoon.',
 'Tagapo', 14.3000, 121.1050, 'resident', 'resolved', false, now() - interval '5 days'),
('#MOCK-2026-06', 'Paolo Santos', 'hazard', 'Structural & Infrastructure',
 'Downed electrical posts or live wires on the road', 'major', 'urgent',
 'Electric post tilted after strong wind. Live wires hang low over the sidewalk.',
 'Labas', 14.3200, 121.1120, 'resident', 'responding', false, now() - interval '1 day'),

-- ── RES-003 jobs ────────────────────────────────────────────────────────────
('#MOCK-2026-07', 'Rosa Aquino', 'accident', 'Medical Emergencies',
 'Motorcycle crashes (habal-habal, motor accidents)', 'major', 'urgent',
 'Habal-habal skidded on the wet curve. Driver conscious with a wound on the arm.',
 'Division Road', 14.3097, 121.1210, 'resident', 'resolved', false, now() - interval '3 days'),
('#MOCK-2026-08', 'Daniel Uy', 'garbage', 'Garbage & Sanitation',
 'Illegal dumping on vacant lots or waterways', 'minor', 'pending',
 'Someone dumps construction debris on the vacant lot at the corner every night.',
 'Pulong Santa Cruz', 14.3030, 121.1120, 'resident', 'resolved', false, now() - interval '4 days'),
('#MOCK-2026-09', 'Katrina Flores', 'crime', 'Community Disturbances',
 'Loud noise / videoke disturbances late at night', 'minor', 'pending',
 'Videoke next door goes past 1 AM on weeknights. Small children cannot sleep.',
 'Aplaya', 14.3010, 121.1090, 'resident', 'responding', false, now() - interval '2 days'),

-- ── RES-004 jobs ────────────────────────────────────────────────────────────
('#MOCK-2026-10', 'Miguel Navarro', 'other', 'Public Health Concerns',
 'Suspected dengue outbreak cluster in a sitio', 'minor', 'pending',
 'Three children in our sitio were hospitalized with dengue this week.',
 'Dila', 14.3130, 121.1090, 'resident', 'resolved', false, now() - interval '3 days'),
('#MOCK-2026-11', 'Sofia Padilla', 'hazard', 'Environmental / Utility Issues',
 'Water supply interruption complaints', 'minor', 'pending',
 'No water supply in our entire block since yesterday morning with no advisory.',
 'Macabling', 14.3050, 121.1170, 'resident', 'resolved', false, now() - interval '5 days'),
('#MOCK-2026-12', 'Tomas Castillo', 'fire', 'Fire (Sunog)',
 'Residential house fires', 'major', 'urgent',
 'Smoke coming from the kitchen of a single-storey house. Family already outside.',
 'Dita', 14.3160, 121.1150, 'resident', 'responding', false, now() - interval '1 day');


-- ── Assignments (resolved rows carry full timestamps for real averages) ─────
insert into assignments
  (report_id, responder_id, status, distance_km, eta_min,
   resolution_notes, created_at, assigned_at, en_route_at, resolved_at)
values
-- RES-001
((select id from reports where report_no = '#MOCK-2026-01'),
 (select id from responders where unit_id = 'RES-001'),
 'resolved', 1.2, 6, 'Floodwater subsided after drainage cleared.',
 now() - interval '2 days', now() - interval '2 days' + interval '12 minutes', now() - interval '2 days' + interval '28 minutes', now() - interval '2 days' + interval '2 hours'),
((select id from reports where report_no = '#MOCK-2026-02'),
 (select id from responders where unit_id = 'RES-001'),
 'resolved', 0.8, 4, 'Missed collection picked up on special trip.',
 now() - interval '4 days', now() - interval '4 days' + interval '20 minutes', now() - interval '4 days' + interval '45 minutes', now() - interval '4 days' + interval '3 hours'),
((select id from reports where report_no = '#MOCK-2026-03'),
 (select id from responders where unit_id = 'RES-001'),
 'en_route', 0.9, 5, null,
 now() - interval '1 day', now() - interval '1 day' + interval '10 minutes', now() - interval '1 day' + interval '22 minutes', null),
-- RES-002
((select id from reports where report_no = '#MOCK-2026-04'),
 (select id from responders where unit_id = 'RES-002'),
 'resolved', 1.5, 7, 'Grass fire put out. Area monitored for rekindling.',
 now() - interval '2 days', now() - interval '2 days' + interval '9 minutes', now() - interval '2 days' + interval '21 minutes', now() - interval '2 days' + interval '90 minutes'),
((select id from reports where report_no = '#MOCK-2026-05'),
 (select id from responders where unit_id = 'RES-002'),
 'resolved', 0.6, 3, 'Bicycle recovered two blocks away and returned to owner.',
 now() - interval '5 days', now() - interval '5 days' + interval '18 minutes', now() - interval '5 days' + interval '33 minutes', now() - interval '5 days' + interval '4 hours'),
((select id from reports where report_no = '#MOCK-2026-06'),
 (select id from responders where unit_id = 'RES-002'),
 'en_route', 2.1, 10, null,
 now() - interval '1 day', now() - interval '1 day' + interval '7 minutes', now() - interval '1 day' + interval '19 minutes', null),
-- RES-003
((select id from reports where report_no = '#MOCK-2026-07'),
 (select id from responders where unit_id = 'RES-003'),
 'resolved', 1.0, 5, 'Patient first-aided on site and brought to the health center.',
 now() - interval '3 days', now() - interval '3 days' + interval '11 minutes', now() - interval '3 days' + interval '24 minutes', now() - interval '3 days' + interval '2 hours'),
((select id from reports where report_no = '#MOCK-2026-08'),
 (select id from responders where unit_id = 'RES-003'),
 'resolved', 1.3, 6, 'Debris hauled to the materials recovery facility. Lot cleared.',
 now() - interval '4 days', now() - interval '4 days' + interval '16 minutes', now() - interval '4 days' + interval '31 minutes', now() - interval '4 days' + interval '3 hours'),
((select id from reports where report_no = '#MOCK-2026-09'),
 (select id from responders where unit_id = 'RES-003'),
 'en_route', 0.7, 4, null,
 now() - interval '2 days', now() - interval '2 days' + interval '8 minutes', now() - interval '2 days' + interval '17 minutes', null),
-- RES-004
((select id from reports where report_no = '#MOCK-2026-10'),
 (select id from responders where unit_id = 'RES-004'),
 'resolved', 0.9, 5, 'Fogging and canal clean-up scheduled with the health office.',
 now() - interval '3 days', now() - interval '3 days' + interval '14 minutes', now() - interval '3 days' + interval '29 minutes', now() - interval '3 days' + interval '150 minutes'),
((select id from reports where report_no = '#MOCK-2026-11'),
 (select id from responders where unit_id = 'RES-004'),
 'resolved', 1.1, 6, 'Water district notified. Supply restored the same evening.',
 now() - interval '5 days', now() - interval '5 days' + interval '22 minutes', now() - interval '5 days' + interval '40 minutes', now() - interval '5 days' + interval '5 hours'),
((select id from reports where report_no = '#MOCK-2026-12'),
 (select id from responders where unit_id = 'RES-004'),
 'en_route', 1.9, 9, null,
 now() - interval '1 day', now() - interval '1 day' + interval '6 minutes', now() - interval '1 day' + interval '15 minutes', null);
