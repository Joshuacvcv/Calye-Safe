-- ============================================================================
-- RESIDENT CONSENT FOR PUBLIC ANNOUNCEMENTS
-- ============================================================================
-- The resident is asked on the submit form whether their report may be
-- uploaded as a public announcement (a warning to nearby residents). The
-- admin's "Dispatch Responder → Upload as Announcement" toggle is only
-- allowed when this flag is true.
--
-- Run this once in the Supabase SQL Editor.
-- ============================================================================

alter table public.reports
  add column if not exists announce_consent boolean not null default false;

comment on column public.reports.announce_consent is
  'Resident consent to publish this report as a public announcement';
