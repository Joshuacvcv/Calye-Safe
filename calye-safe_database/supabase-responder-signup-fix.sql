-- ============================================================================
-- Calye-Safe — FIX: responder sign-up fails with "Database error saving
-- new user" (resident sign-up works fine)
--
-- ROOT CAUSE:
--   Sign-up inserts auth.users -> handle_new_user() (SECURITY DEFINER, so the
--   profiles INSERT itself always succeeds) -> chained row triggers fire:
--     1. trg_auto_assign_responder_unit  (BEFORE, invoker rights)
--        SELECTs max(unit_id) FROM responders
--     2. trg_sync_responder_from_profile (AFTER, invoker rights)
--        INSERTs the new unit row INTO responders
--     3. trg_sync_profile_from_responder (AFTER, invoker rights)
--        UPDATEs profiles with the assigned unit_id
--   With production RLS enabled, `responders` has NO insert policy for a
--   brand-new user, so step 2 raises a row-level-security violation. The
--   error aborts the whole chain, the auth.users INSERT rolls back, and
--   Supabase Auth reports "Database error saving new user".
--   Residents never touch this chain (role <> 'responder'), which is why
--   only responder registration breaks.
--
-- FIX (same pattern as supabase-notifications-rls-fix.sql):
--   Recreate the three chained functions as SECURITY DEFINER so their
--   internal SELECT / INSERT / UPDATE run as the owner and bypass RLS.
--   Direct app access to `responders` stays locked down by RLS; only these
--   internal functions bypass it. As a bonus, unit numbering now sees the
--   true MAX(unit_id) instead of the RLS-filtered view.
--
-- SECOND BUG FIXED HERE (infinite trigger recursion):
--   profiles -> responders -> profiles ping-pong forever, because Postgres
--   fires AFTER UPDATE triggers even when the new values are identical:
--     profiles INSERT → responders INSERT → profiles UPDATE (same values)
--     → responders UPDATE (same values) → profiles UPDATE … ad infinitum
--   …until "stack depth limit exceeded" aborts signup with the SAME
--   user-visible message. (Seed rows never looped only because their
--   back-sync matched zero profile rows.) Both sync functions below therefore
--   write ONLY on actual change (IS DISTINCT FROM): each direction equalizes
--   state, so the return trip always finds nothing to do and stops.
--   (On INSERT, OLD.* is all-NULL, so the guard passes and the cascade runs.)
--
-- HOW TO USE: paste the whole file into the Supabase SQL Editor and RUN.
-- Idempotent — CREATE OR REPLACE keeps existing triggers working (they call
-- these functions by name, so no trigger recreation is needed).
-- ============================================================================


-- ── 1. Auto-assign unit_id (BEFORE trigger helper) ───────────────────────────
create or replace function auto_assign_responder_unit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_next int;
begin
  if new.role = 'responder' and (new.unit_id is null or new.unit_id = '') then
    select coalesce(max((regexp_replace(unit_id, '\D', '', 'g'))::int), 0) + 1
      into v_next
    from public.responders
    where unit_id ~ '^RES-[0-9]+$';
    new.unit_id := 'RES-' || lpad(v_next::text, 3, '0');
  end if;
  return new;
end $$;


-- ── 2. Sync profile -> responders row (AFTER trigger helper) ─────────────────
create or replace function sync_responder_from_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.role = 'responder' and new.unit_id is not null
     and (old.unit_id is distinct from new.unit_id
          or old.full_name is distinct from new.full_name
          or old.role is distinct from new.role) then
    insert into public.responders (unit_id, name, vehicle, agency)
    values (new.unit_id, new.full_name, '', 'Barangay Calye QRT')
    on conflict (unit_id) do update set
      name = excluded.name;
  end if;
  return new;
end $$;


-- ── 3. Sync responders -> profile back (AFTER trigger helper) ────────────────
create or replace function sync_profile_from_responder()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.profiles
  set unit_id = new.unit_id,
      full_name = new.name
  where (unit_id = old.unit_id or unit_id = new.unit_id)
    and (unit_id is distinct from new.unit_id
         or full_name is distinct from new.name);
  return new;
end $$;


-- ── 4. VERIFY ────────────────────────────────────────────────────────────────
-- After running, register a test responder in the app. Then check:
--   select id, full_name, role, unit_id, verification_status
--   from profiles where role = 'responder' order by created_at desc limit 3;
--   select unit_id, name from responders order by unit_id desc limit 5;
-- The new account should have unit_id RES-0xx in BOTH tables.
