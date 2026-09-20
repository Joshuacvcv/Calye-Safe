-- ============================================================================
-- Calye-Safe — ONE PENDING verification request per user
--
-- PROBLEM: one user submitted 3 identical pending rows (double-clicks /
-- re-uploads), flooding the admin Verification Queue. The app now blocks
-- resubmission while a request is pending (see submitVerification in
-- supabase-auth.js), but client checks can be bypassed or raced — so the
-- rule is enforced here, at the database level.
--
-- WHAT THIS DOES:
--   1. Cleans up existing duplicates: keeps each user's EARLIEST pending
--      request, deletes the newer ones.
--   2. Adds a PARTIAL unique index: at most one 'pending' row per user_id.
--      Reviewed rows (approved/rejected) are unaffected, so a rejected user
--      can still resubmit exactly once.
--
-- HOW TO USE: paste the whole file into the Supabase SQL Editor and RUN.
-- Idempotent — safe to re-run.
-- ============================================================================


-- ── 1. Collapse existing duplicate pending rows (keep the earliest) ──────────
delete from verification_requests a
using verification_requests b
where a.status = 'pending'
  and b.status = 'pending'
  and a.user_id = b.user_id
  and (a.submitted_at, a.id) > (b.submitted_at, b.id);


-- ── 2. Enforce one pending request per user from now on ──────────────────────
create unique index if not exists uq_verification_one_pending
  on verification_requests (user_id)
  where status = 'pending';


-- ── 3. VERIFY ────────────────────────────────────────────────────────────────
-- No user should appear more than once:
--   select user_id, count(*) from verification_requests
--   where status = 'pending' group by user_id having count(*) > 1;
-- (Expect zero rows.)
