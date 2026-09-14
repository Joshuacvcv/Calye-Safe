-- ============================================================================
-- Calye-Safe — MOCK incidents for checking (TEST DATA ONLY)
--
-- 30 reports: 3 per incident group (1 pending + 1 responding + 1 resolved),
-- using the exact group names, subtypes, severities and categories the
-- resident app submits. Responding/resolved rows get assignments spread
-- across RES-001 / RES-002 / RES-003 so the responder queue, admin
-- timeline, and performance tab all have something to show.
--
-- HOW TO USE: paste the whole file into the Supabase SQL Editor and RUN.
--   Prerequisites: base schema + timeline/map triggers applied, responders
--   RES-001..003 present, subtype column applied.
--   Report timelines + map pins are created automatically by DB triggers.
--
-- CLEANUP (run when done checking):
--   create temp table test_rep_ids as
--     select id from reports where report_no like '#TEST-%';
--   delete from map_incidents where report_id in (select id from test_rep_ids);
--   delete from assignment_timeline where assignment_id in
--     (select id from assignments where report_id in (select id from test_rep_ids));
--   delete from assignments where report_id in (select id from test_rep_ids);
--   delete from reports where id in (select id from test_rep_ids);
--   (report_timeline rows cascade automatically.)
-- ============================================================================

insert into reports
  (report_no, reporter_name, category, type, subtype, severity, priority,
   description, location, lat, lng, source, status, announce_consent, created_at)
values
-- ── 1. Natural Disasters & Flooding ─────────────────────────────────────────
('#TEST-2026-001', 'Maria Santos', 'flood', 'Natural Disasters & Flooding',
 'Flash floods / rising floodwater (baha)', 'major', 'urgent',
 'Ankle-deep floodwater rising fast on our street after one hour of heavy rain. Several houses starting to flood inside.',
 'Mercado Village', 14.2989, 121.1163, 'resident', 'pending', true, now() - interval '2 hours'),
('#TEST-2026-002', 'Jose Ramos', 'flood', 'Natural Disasters & Flooding',
 'Creek or estero overflow', 'major', 'pending',
 'Calye creek overflowed onto the footpath. Water is knee-deep near the crossing, passable only by trucks.',
 'Calye Creek', 14.3110, 121.1130, 'resident', 'responding', false, now() - interval '1 day'),
('#TEST-2026-003', 'Ana Villanueva', 'flood', 'Natural Disasters & Flooding',
 'Clogged drainage causing severe flooding', 'major', 'pending',
 'Drainage canal behind our row of houses is blocked with garbage and the yard flooded last night. Water has subsided now.',
 'Purok 5', 14.3128, 121.1112, 'resident', 'resolved', false, now() - interval '4 days'),

-- ── 2. Fire (Sunog) ─────────────────────────────────────────────────────────
('#TEST-2026-004', 'Ramon Ocampo', 'fire', 'Fire (Sunog)',
 'Grass fires / cogon fires near communities', 'major', 'pending',
 'Cogon grass burning at the vacant lot beside the chapel. Smoke is reaching nearby houses.',
 'Purok 3', 14.3096, 121.1160, 'resident', 'pending', true, now() - interval '5 hours'),
('#TEST-2026-005', 'Liza Fernandez', 'fire', 'Fire (Sunog)',
 'Residential house fires', 'major', 'urgent',
 'Fire started on the second floor of a two-storey house. Family is out safely but the fire is spreading to the roof.',
 'Dita', 14.3160, 121.1150, 'resident', 'responding', false, now() - interval '2 days'),
('#TEST-2026-006', 'Mark Reyes', 'fire', 'Fire (Sunog)',
 'Electrical fire from faulty wiring', 'major', 'pending',
 'Sparks and smoke came from an overloaded outlet in a sari-sari store. Put out with a fire extinguisher before firemen arrived.',
 'Balibago', 14.3050, 121.1080, 'resident', 'resolved', false, now() - interval '5 days'),

-- ── 3. Crime & Public Safety ─────────────────────────────────────────────────
('#TEST-2026-007', 'Jenny Cruz', 'crime', 'Crime & Public Safety',
 'Theft (vehicle, livestock, valuables)', 'major', 'pending',
 'My motorcycle parked outside our gate was stolen last night between 1 AM and 4 AM. Has a red helmet box at the back.',
 'Tagapo', 14.3000, 121.1050, 'resident', 'pending', true, now() - interval '8 hours'),
('#TEST-2026-008', 'Paolo Gutierrez', 'crime', 'Crime & Public Safety',
 'Robbery / hold-up incidents', 'major', 'urgent',
 'Two men on a motorcycle held up a convenience store along the highway and took the cash register. They fled toward the plaza.',
 'National Highway', 14.3170, 121.1090, 'resident', 'responding', false, now() - interval '1 day'),
('#TEST-2026-009', 'Rosa Mendoza', 'crime', 'Crime & Public Safety',
 'Missing persons (especially children or elderly)', 'major', 'pending',
 'My 78-year-old father with memory problems left the house yesterday afternoon and has not returned. Last seen near the market.',
 'Market Area', 14.3122, 121.1114, 'resident', 'resolved', false, now() - interval '3 days'),

-- ── 4. Medical Emergencies ───────────────────────────────────────────────────
('#TEST-2026-010', 'Daniel Torres', 'accident', 'Medical Emergencies',
 'Motorcycle crashes (habal-habal, motor accidents)', 'major', 'urgent',
 'A habal-habal motorcycle skidded on the wet curve and the driver is unconscious with a bleeding head wound. Needs ambulance now.',
 'Division Road', 14.3097, 121.1210, 'resident', 'pending', true, now() - interval '1 hour'),
('#TEST-2026-011', 'Katrina Uy', 'accident', 'Medical Emergencies',
 'Vehicular accidents', 'major', 'pending',
 'A tricycle and a sedan collided at the intersection. One passenger has a possible broken arm. Traffic is building up.',
 'Pook', 14.3130, 121.1180, 'resident', 'responding', false, now() - interval '2 days'),
('#TEST-2026-012', 'Miguel Santos', 'accident', 'Medical Emergencies',
 'Sudden cardiac arrest or stroke in a public area', 'major', 'pending',
 'An elderly man collapsed while waiting at the tricycle terminal. A nurse bystander started CPR until medics arrived.',
 'Sinalhan', 14.2950, 121.1100, 'resident', 'resolved', false, now() - interval '6 days'),

-- ── 5. Structural & Infrastructure ──────────────────────────────────────────
('#TEST-2026-013', 'Edgar Bautista', 'hazard', 'Structural & Infrastructure',
 'Downed electrical posts or live wires on the road', 'major', 'urgent',
 'An electric post tilted after last nights wind and live wires are now hanging low over the sidewalk where children pass.',
 'Labas', 14.3200, 121.1120, 'resident', 'pending', true, now() - interval '3 hours'),
('#TEST-2026-014', 'Nora Aquino', 'hazard', 'Structural & Infrastructure',
 'Collapsed structures (bahay-bahay)', 'major', 'pending',
 'The hollow-block perimeter wall of an old warehouse collapsed onto the sidewalk after days of rain. No one was hurt.',
 'Malusak', 14.3080, 121.1040, 'resident', 'responding', false, now() - interval '2 days'),
('#TEST-2026-015', 'Victor Lim', 'hazard', 'Structural & Infrastructure',
 'Bridge damage or collapse risk', 'major', 'pending',
 'A crack widened on the small footbridge railings and one section is wobbling. Barangay tanods cordoned it off temporarily.',
 'Ibaba', 14.3060, 121.1140, 'resident', 'resolved', false, now() - interval '5 days'),

-- ── 6. Road & Infrastructure Hazards ────────────────────────────────────────
('#TEST-2026-016', 'Grace Padilla', 'hazard', 'Road & Infrastructure Hazards',
 'Potholes and road deterioration (malalim na butas sa kalsada)', 'minor', 'pending',
 'A very deep pothole opened up in the middle of the lane. Two motorcycles already had flat tires this week.',
 'Calye Street', 14.3105, 121.1092, 'resident', 'pending', true, now() - interval '6 hours'),
('#TEST-2026-017', 'Henry Navarro', 'hazard', 'Road & Infrastructure Hazards',
 'Broken or flickering streetlights (sira na ilaw sa daan)', 'minor', 'pending',
 'Three consecutive streetlights along the park pathway are out, leaving the whole stretch pitch dark at night.',
 'Calye Park', 14.3135, 121.1078, 'resident', 'responding', false, now() - interval '3 days'),
('#TEST-2026-018', 'Irene Castillo', 'hazard', 'Road & Infrastructure Hazards',
 'Fallen trees blocking roads after storms', 'minor', 'pending',
 'A mango tree fell across half the barangay road during the storm. Tricycles cannot pass through.',
 'Bankley Area', 14.3090, 121.1128, 'resident', 'resolved', false, now() - interval '4 days'),

-- ── 7. Garbage & Sanitation ─────────────────────────────────────────────────
('#TEST-2026-019', 'Joel Ramos', 'garbage', 'Garbage & Sanitation',
 'Uncollected garbage / missed collection schedule', 'minor', 'pending',
 'Garbage truck skipped our street two collections in a row. Bags are piling up and starting to smell.',
 'Phase 2', 14.3075, 121.1100, 'resident', 'pending', true, now() - interval '9 hours'),
('#TEST-2026-020', 'Karen David', 'garbage', 'Garbage & Sanitation',
 'Illegal dumping on vacant lots or waterways', 'minor', 'pending',
 'Someone keeps dumping construction debris and household trash on the vacant lot at the corner every night.',
 'Pulong Santa Cruz', 14.3030, 121.1120, 'resident', 'responding', false, now() - interval '1 day'),
('#TEST-2026-021', 'Leo Marquez', 'garbage', 'Garbage & Sanitation',
 'Burning of trash in residential areas (open burning)', 'minor', 'pending',
 'A neighbor burns plastic and rubber every afternoon and the smoke triggers my childs asthma. Already talked to them twice.',
 'Santo Domingo', 14.3100, 121.1070, 'resident', 'resolved', false, now() - interval '6 days'),

-- ── 8. Community Disturbances ───────────────────────────────────────────────
('#TEST-2026-022', 'Mona Reyes', 'crime', 'Community Disturbances',
 'Loud noise / videoke disturbances late at night', 'minor', 'pending',
 'Videoke singing next door goes past 2 AM on weeknights. We have small children who cannot sleep.',
 'Aplaya', 14.3010, 121.1090, 'resident', 'pending', true, now() - interval '4 hours'),
('#TEST-2026-023', 'Nico Santiago', 'crime', 'Community Disturbances',
 'Stray animals causing road hazards or biting incidents', 'minor', 'pending',
 'A pack of stray dogs chases motorcycles every morning at the corner and one nearly bit a student yesterday.',
 'Caingin', 14.3180, 121.1140, 'resident', 'responding', false, now() - interval '2 days'),
('#TEST-2026-024', 'Olga Perez', 'crime', 'Community Disturbances',
 'Vandalism and graffiti on public property', 'minor', 'pending',
 'The waiting shed walls were spray-painted overnight. We organized a repaint with youth volunteers.',
 'Kanluran', 14.3090, 121.1060, 'resident', 'resolved', false, now() - interval '5 days'),

-- ── 9. Environmental / Utility Issues ───────────────────────────────────────
('#TEST-2026-025', 'Pedro Aguilar', 'hazard', 'Environmental / Utility Issues',
 'Water supply interruption complaints', 'minor', 'pending',
 'No water supply in our entire block since yesterday morning with no advisory. Deep well queue is very long.',
 'Macabling', 14.3050, 121.1170, 'resident', 'pending', true, now() - interval '7 hours'),
('#TEST-2026-026', 'Quennie Flores', 'hazard', 'Environmental / Utility Issues',
 'Electrical wire hazards (hanging wires, exposed cables)', 'minor', 'pending',
 'A bundle of electric and cable wires hangs down to head level across the alley after a truck snagged them.',
 'Malitlit', 14.3110, 121.1190, 'resident', 'responding', false, now() - interval '3 days'),
('#TEST-2026-027', 'Rene Villanueva', 'hazard', 'Environmental / Utility Issues',
 'Sewage or septic tank overflow onto streets', 'minor', 'pending',
 'Septic overflow from an old apartment is running onto the street and smells bad, especially when it rains.',
 'Don Jose', 14.3000, 121.1130, 'resident', 'resolved', false, now() - interval '6 days'),

-- ── 10. Public Health Concerns ──────────────────────────────────────────────
('#TEST-2026-028', 'Sofia Enriquez', 'other', 'Public Health Concerns',
 'Suspected dengue outbreak cluster in a sitio', 'minor', 'pending',
 'Four children in our sitio were hospitalized with dengue this week. There are many mosquito breeding spots in clogged canals.',
 'Dila', 14.3130, 121.1090, 'resident', 'pending', true, now() - interval '5 hours'),
('#TEST-2026-029', 'Tomas Rivera', 'other', 'Public Health Concerns',
 'Stray dog bites (rabies risk)', 'minor', 'urgent',
 'A stray dog bit my 9-year-old on the leg this morning. The wound was washed but we need guidance on anti-rabies shots.',
 'Dita', 14.3165, 121.1155, 'resident', 'responding', false, now() - interval '1 day'),
('#TEST-2026-030', 'Uma Dizon', 'other', 'Public Health Concerns',
 'Food stall or carinderia sanitation complaints', 'minor', 'pending',
 'A street food stall reuses cooking oil for days and has no handwashing setup. Several customers got stomach aches.',
 'Market Area', 14.3125, 121.1118, 'resident', 'resolved', false, now() - interval '4 days');


-- ── Assignments: responding rows are en_route, resolved rows are resolved ───
-- Round-robin across RES-001 / RES-002 / RES-003.
insert into assignments
  (report_id, responder_id, status, distance_km, eta_min,
   resolution_notes, created_at, assigned_at, en_route_at, resolved_at)
values
-- responding (en_route)
((select id from reports where report_no = '#TEST-2026-002'),
 (select id from responders where unit_id = 'RES-001'),
 'en_route', 1.1, 5, null,
 now() - interval '1 day', now() - interval '1 day' + interval '12 minutes', now() - interval '1 day' + interval '25 minutes', null),
((select id from reports where report_no = '#TEST-2026-005'),
 (select id from responders where unit_id = 'RES-002'),
 'en_route', 2.0, 8, null,
 now() - interval '2 days', now() - interval '2 days' + interval '10 minutes', now() - interval '2 days' + interval '22 minutes', null),
((select id from reports where report_no = '#TEST-2026-008'),
 (select id from responders where unit_id = 'RES-003'),
 'en_route', 1.5, 7, null,
 now() - interval '1 day', now() - interval '1 day' + interval '8 minutes', now() - interval '1 day' + interval '20 minutes', null),
((select id from reports where report_no = '#TEST-2026-011'),
 (select id from responders where unit_id = 'RES-001'),
 'en_route', 0.9, 4, null,
 now() - interval '2 days', now() - interval '2 days' + interval '15 minutes', now() - interval '2 days' + interval '28 minutes', null),
((select id from reports where report_no = '#TEST-2026-014'),
 (select id from responders where unit_id = 'RES-002'),
 'en_route', 1.8, 9, null,
 now() - interval '2 days', now() - interval '2 days' + interval '11 minutes', now() - interval '2 days' + interval '24 minutes', null),
((select id from reports where report_no = '#TEST-2026-017'),
 (select id from responders where unit_id = 'RES-003'),
 'en_route', 0.6, 3, null,
 now() - interval '3 days', now() - interval '3 days' + interval '9 minutes', now() - interval '3 days' + interval '18 minutes', null),
((select id from reports where report_no = '#TEST-2026-020'),
 (select id from responders where unit_id = 'RES-001'),
 'en_route', 1.3, 6, null,
 now() - interval '1 day', now() - interval '1 day' + interval '14 minutes', now() - interval '1 day' + interval '30 minutes', null),
((select id from reports where report_no = '#TEST-2026-023'),
 (select id from responders where unit_id = 'RES-002'),
 'en_route', 0.7, 4, null,
 now() - interval '2 days', now() - interval '2 days' + interval '7 minutes', now() - interval '2 days' + interval '16 minutes', null),
((select id from reports where report_no = '#TEST-2026-026'),
 (select id from responders where unit_id = 'RES-003'),
 'en_route', 2.2, 10, null,
 now() - interval '3 days', now() - interval '3 days' + interval '13 minutes', now() - interval '3 days' + interval '27 minutes', null),
((select id from reports where report_no = '#TEST-2026-029'),
 (select id from responders where unit_id = 'RES-001'),
 'en_route', 1.0, 5, null,
 now() - interval '1 day', now() - interval '1 day' + interval '6 minutes', now() - interval '1 day' + interval '15 minutes', null),
-- resolved
((select id from reports where report_no = '#TEST-2026-003'),
 (select id from responders where unit_id = 'RES-002'),
 'resolved', 1.0, 5, 'Drainage unclogged and floodwater subsided. Area cleared.',
 now() - interval '4 days', now() - interval '4 days' + interval '20 minutes', now() - interval '4 days' + interval '35 minutes', now() - interval '4 days' + interval '3 hours'),
((select id from reports where report_no = '#TEST-2026-006'),
 (select id from responders where unit_id = 'RES-003'),
 'resolved', 1.6, 7, 'Outlet replaced and wiring secured. Fire marshal notified.',
 now() - interval '5 days', now() - interval '5 days' + interval '25 minutes', now() - interval '5 days' + interval '40 minutes', now() - interval '5 days' + interval '2 hours'),
((select id from reports where report_no = '#TEST-2026-009'),
 (select id from responders where unit_id = 'RES-001'),
 'resolved', 0.5, 3, 'Senior citizen found safe at a relatives house and reunited with family.',
 now() - interval '3 days', now() - interval '3 days' + interval '15 minutes', now() - interval '3 days' + interval '30 minutes', now() - interval '3 days' + interval '4 hours'),
((select id from reports where report_no = '#TEST-2026-012'),
 (select id from responders where unit_id = 'RES-002'),
 'resolved', 0.8, 4, 'Patient stabilized by medics and transported to the district hospital.',
 now() - interval '6 days', now() - interval '6 days' + interval '10 minutes', now() - interval '6 days' + interval '18 minutes', now() - interval '6 days' + interval '1 hour'),
((select id from reports where report_no = '#TEST-2026-015'),
 (select id from responders where unit_id = 'RES-003'),
 'resolved', 1.4, 6, 'Footbridge cordoned and temporary braces installed. Engineering office scheduled for repair.',
 now() - interval '5 days', now() - interval '5 days' + interval '30 minutes', now() - interval '5 days' + interval '50 minutes', now() - interval '5 days' + interval '5 hours'),
((select id from reports where report_no = '#TEST-2026-018'),
 (select id from responders where unit_id = 'RES-001'),
 'resolved', 0.7, 4, 'Fallen tree cut and hauled away. Road fully passable.',
 now() - interval '4 days', now() - interval '4 days' + interval '20 minutes', now() - interval '4 days' + interval '35 minutes', now() - interval '4 days' + interval '2 hours'),
((select id from reports where report_no = '#TEST-2026-021'),
 (select id from responders where unit_id = 'RES-002'),
 'resolved', 0.9, 5, 'Resident educated on waste segregation schedule. No repeat offense recorded.',
 now() - interval '6 days', now() - interval '6 days' + interval '18 minutes', now() - interval '6 days' + interval '30 minutes', now() - interval '6 days' + interval '3 hours'),
((select id from reports where report_no = '#TEST-2026-024'),
 (select id from responders where unit_id = 'RES-003'),
 'resolved', 0.4, 2, 'Graffiti painted over by youth volunteers with barangay paint supplies.',
 now() - interval '5 days', now() - interval '5 days' + interval '22 minutes', now() - interval '5 days' + interval '38 minutes', now() - interval '5 days' + interval '2 hours'),
((select id from reports where report_no = '#TEST-2026-027'),
 (select id from responders where unit_id = 'RES-001'),
 'resolved', 1.2, 6, 'Septic tank desludged and street disinfected by sanitation team.',
 now() - interval '6 days', now() - interval '6 days' + interval '25 minutes', now() - interval '6 days' + interval '45 minutes', now() - interval '6 days' + interval '4 hours'),
((select id from reports where report_no = '#TEST-2026-030'),
 (select id from responders where unit_id = 'RES-002'),
 'resolved', 0.3, 2, 'Stall owner complied: fresh oil daily and handwashing station installed.',
 now() - interval '4 days', now() - interval '4 days' + interval '16 minutes', now() - interval '4 days' + interval '28 minutes', now() - interval '4 days' + interval '3 hours');
