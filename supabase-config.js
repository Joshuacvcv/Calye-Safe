/**
 * Calye-Safe — Supabase client configuration
 *
 * Load BEFORE supabase-data.js and after the supabase-js CDN script.
 *
 *   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
 *   <script src="supabase-config.js"></script>
 *   <script src="supabase-data.js"></script>
 *
 * CONFIG CLEAN-UP (quiet commit for the static host):
 *   The anon key below is NOT a secret — any client can read it, and it is
 *   sent to the browser in every page load. Storing it in this file is fine
 *   functionally. This module, however, can be overridden at deploy time so
 *   your git tree can ship without the key hardcoded:
 *
 *     Option A — host injects it BEFORE this file loads:
 *       <script>window.CALYE_SUPABASE_ENV = { url: '…', anonKey: '…' };</script>
 *       <script src="supabase-config.js"></script>
 *
 *     Option B — a gitignored supabase-config.env.js (see .gitignore) loaded
 *       just before this file sets the same global. Deployers copy the
 *       committed supabase-config.env.example.js template and fill it in.
 *
 *   If neither is present we fall back to the committed project values below,
 *   which keeps local dev and the headless stress harness working out of the
 *   box. The REAL secret (service_role key) must never be added here or to
 *   GitHub Pages; it only lives server-side in the Supabase dashboard.
 */
window.CALYE_SUPABASE = (function () {
  var URL = 'https://dltyttngbrenbwdsaiwg.supabase.co';
  var ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRsdHl0dG5nYnJlbmJ3ZHNhaXdnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU1MDYzMDMsImV4cCI6MjEwMTA4MjMwM30.0F96Q3TUQ4IFZnlcOtXiGP5FtTt6F6fthiC5a9kJE6E';

  // Deploy-time override (see options A / B above). Purely cosmetic for a
  // static SPA — the value still lands in the browser either way.
  if (window.CALYE_SUPABASE_ENV && window.CALYE_SUPABASE_ENV.url) {
    URL = window.CALYE_SUPABASE_ENV.url;
  }
  if (window.CALYE_SUPABASE_ENV && window.CALYE_SUPABASE_ENV.anonKey) {
    ANON_KEY = window.CALYE_SUPABASE_ENV.anonKey;
  }

  var client = null;
  var ready = false;

  function init(storageKey) {
    try {
      if (typeof window.supabase !== 'undefined' && window.supabase.createClient) {
        // Isolate each app's session behind its own storage key so signing
        // into the resident app in another tab can never replace the admin
        // dashboard's (or responder app's) auth token. Without this, a
        // cross-tab login clobbers the shared session and privileged RPCs
        // run as the wrong user (e.g. "Admin privileges required. role=resident").
        var opts = { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } };
        if (storageKey) opts.auth.storageKey = storageKey;
        client = window.supabase.createClient(URL, ANON_KEY, opts);
        ready = true;
      }
    } catch (e) {
      client = null;
      ready = false;
    }
    return ready;
  }

  function isReady() {
    return ready && !!client;
  }

  function getClient() {
    return client;
  }

  return {
    url: URL,
    anonKey: ANON_KEY,
    init: init,
    isReady: isReady,
    getClient: getClient
  };
})();
