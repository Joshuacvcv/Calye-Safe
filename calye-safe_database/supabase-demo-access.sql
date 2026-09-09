-- ============================================================================
-- Calye-Safe — DEMO-ONLY ACCESS MIGRATION
--
-- Run AFTER supabase-schema.sql + supabase-seed.sql.
--
-- WHY THIS EXISTS:
--   The prototype apps use "any email/password works" demo logins, so they do
--   NOT create real Supabase Auth sessions. The RLS policies in
--   supabase-schema.sql only let a logged-in user read reports / assignments /
--   responders / profiles — with the anon key those queries return 0 rows.
--
--   For the demo/prototype, this migration turns RLS OFF so the anon key can
--   read and write every table (exactly like the old localStorage behaviour).
--
--   !!! DO NOT USE THIS IN PRODUCTION !!!
--   Before going live: re-enable RLS and wire the apps to supabase.auth
--   (signUp / signInWithPassword). The policies in supabase-schema.sql are
--   then enforced automatically.
-- ============================================================================

alter table public.profiles            disable row level security;
alter table public.reports             disable row level security;
alter table public.report_timeline     disable row level security;
alter table public.report_media        disable row level security;
alter table public.responders          disable row level security;
alter table public.assignments         disable row level security;
alter table public.assignment_timeline disable row level security;
alter table public.resolved_history    disable row level security;
alter table public.announcements       disable row level security;
alter table public.hotlines            disable row level security;
alter table public.map_incidents       disable row level security;
alter table public.verification_requests disable row level security;
alter table public.notifications       disable row level security;

-- To restore security before production:
--   alter table public.profiles            enable row level security;
--   alter table public.reports             enable row level security;
--   alter table public.report_timeline     enable row level security;
--   alter table public.report_media        enable row level security;
--   alter table public.responders          enable row level security;
--   alter table public.assignments         enable row level security;
--   alter table public.assignment_timeline enable row level security;
--   alter table public.resolved_history    enable row level security;
--   alter table public.announcements       enable row level security;
--   alter table public.hotlines            enable row level security;
--   alter table public.map_incidents       enable row level security;
--   alter table public.notifications       enable row level security;

-- ============================================================================
-- VERIFICATION (run this after the ALTERs above; expect ZERO rows returned)
-- ============================================================================
-- select schemaname, tablename
-- from pg_tables
-- where schemaname = 'public'
--   and tablename in ('profiles','reports','report_timeline','report_media',
--                     'responders','assignments','assignment_timeline',
--                     'resolved_history','announcements','hotlines',
--                     'map_incidents','verification_requests','notifications')
--   and rowsecurity;
