-- ============================================================================
-- Calye-Safe — PUSH WEBHOOK TRIGGER (manual pg_net version)
--
-- WHY THIS FILE:
--   The dashboard's Integrations → Webhooks creator fails on this project
--   with "schema supabase_functions does not exist". This does the same job
--   directly: AFTER INSERT on notifications → POST the row to send-push.
--
-- DESIGN:
--   * net.http_post only ENQUEUES the request (background worker) — a slow
--     or failing function can never block or break the notification insert.
--   * Auth is a random shared secret (NOT any Supabase key): it lives in
--     Vault under push_webhook_key AND as the PUSH_WEBHOOK_KEY function
--     secret. The service_role key is not needed anywhere in this flow.
--   * Payload shape matches what send-push expects:
--       { "type": "INSERT", "record": { user_id, title, body, type,
--         related_report_id, related_assignment_id, ... } }
--
-- RUN IN THE SUPABASE SQL EDITOR, IN THIS ORDER:
--   1. This whole file (extension + function + trigger).
--   2. Generate a secret (PowerShell on your PC, copy the line it prints):
--        [Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Maximum 256 }))
--      Store it in Vault (Supabase SQL Editor, run once):
--        select vault.create_secret('<PASTE-GENERATED-STRING>', 'push_webhook_key');
--      And as the PUSH_WEBHOOK_KEY secret on the send-push function.
--      (The same string in both places. It never goes in the repo.)
--   3. Test: insert one notifications row for your own user_id, then check
--      Edge Functions -> send-push -> Logs.
--
-- ROLLBACK: drop trigger trg_send_push on notifications;
-- ============================================================================

create extension if not exists pg_net;

create or replace function public.notify_send_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url     text := 'https://dltyttngbrenbwdsaiwg.supabase.co/functions/v1/send-push';
  v_key     text;
  v_payload jsonb;
begin
  select s.decrypted_secret into v_key
    from vault.decrypted_secrets s
   where s.name = 'push_webhook_key'
   limit 1;

  if v_key is null or v_key = '' then
    return new; -- key not stored yet: skip silently, never break the insert
  end if;

  -- Sanitize: pastes often smuggle in newlines/spaces or surrounding quotes,
  -- which makes the functions gateway reject the JWT before our code runs.
  -- Mirror a real supabase-js client: send BOTH apikey and Authorization.
  v_key := regexp_replace(v_key, '^\s+|\s+$', '', 'g');
  v_key := regexp_replace(v_key, '^"|"$', '', 'g');

  v_payload := jsonb_build_object('type', 'INSERT', 'record', row_to_json(NEW));

  begin
    perform net.http_post(
      url                  := v_url,
      body                 := v_payload,
      headers              := jsonb_build_object(
                                'Content-Type', 'application/json',
                                'apikey', v_key,
                                'Authorization', 'Bearer ' || v_key
                              ),
      timeout_milliseconds := 8000
    );
  exception when others then
    null; -- enqueue failure must never break the notification insert
  end;

  return new;
end;
$$;

drop trigger if exists trg_send_push on public.notifications;

create trigger trg_send_push
  after insert on public.notifications
  for each row execute function public.notify_send_push();

-- ============================================================================
-- VERIFY AFTER RUNNING:
--   select tgname, tgenabled from pg_trigger where tgname = 'trg_send_push';
-- Must return one enabled row. Then do step 2 (Vault secret) above.
-- ============================================================================
