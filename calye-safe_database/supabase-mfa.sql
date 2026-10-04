-- ============================================================================
-- Calye-Safe — STAFF MFA ENFORCEMENT FLAG
--
-- WHY:
--   TOTP enrollment UI ships in the admin console (opt-in). Nothing is
--   enforced until you flip a per-account flag here — so staff can enroll
--   first and nobody gets locked out mid-cutover.
--
-- HOW TO ROLL OUT:
--   1. Run this whole file in the Supabase SQL editor (safe to re-run).
--   2. Ask each staffer to sign in → accept the setup prompt → scan the
--      code with Google Authenticator / Authy / 1Password.
--   3. Confirm in Authentication > Users that each has a verified MFA factor.
--   4. Then enforce per account with the statement at the bottom
--      (replace the email). From the next sign-in, that account must pass
--      the authenticator challenge before the dashboard boots.
--
-- SAFETY:
--   * One nullable column, default false — existing behavior is unchanged
--     until you explicitly set it true for someone.
--   * The admin gate reads it defensively: if the column is missing, the
--     check is simply skipped.
-- ============================================================================

alter table public.profiles
  add column if not exists mfa_enforced boolean not null default false;

comment on column public.profiles.mfa_enforced is
  'Staff/admin only: require a verified TOTP challenge at every sign-in.';

-- ── Enforce for one staffer (run after they enroll + verify) ────────────────
-- update public.profiles
--    set mfa_enforced = true
--  where email = 'staffer@example.com'
--    and role in ('staff', 'admin');

-- ── Roll back for one staffer (lost phone) ───────────────────────────────────
-- update public.profiles
--    set mfa_enforced = false
--  where email = 'staffer@example.com';
