-- ============================================================================
-- Calye-Safe — email-registered check (lets login say WHICH field is wrong)
-- ----------------------------------------------------------------------------
-- The login pages call this after a failed sign-in: if the email is unknown
-- the error goes under Email ("Incorrect email"), otherwise under Password
-- ("Incorrect password"). Without this function the apps fall back to a
-- generic "Invalid login credentials" under the password field.
--
-- Run this whole script ONCE in the Supabase SQL editor.
-- Note: this intentionally reveals whether an email is registered (needed
-- to name the faulty field). Acceptable for a barangay app; do not use if
-- you require strict anti-enumeration.
-- ============================================================================

create or replace function is_email_registered(p_email text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from auth.users u
    where lower(u.email) = lower(nullif(trim(p_email), ''))
  );
$$;

grant execute on function is_email_registered(text) to anon, authenticated;
