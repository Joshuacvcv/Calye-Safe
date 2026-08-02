/**
 * Calye-Safe — Supabase client configuration
 *
 * Load BEFORE supabase-data.js and after the supabase-js CDN script.
 *
 *   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
 *   <script src="supabase-config.js"></script>
 *   <script src="supabase-data.js"></script>
 */
window.CALYE_SUPABASE = (function () {
  var URL = 'https://dltyttngbrenbwdsaiwg.supabase.co';
  var ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRsdHl0dG5nYnJlbmJ3ZHNhaXdnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU1MDYzMDMsImV4cCI6MjEwMTA4MjMwM30.0F96Q3TUQ4IFZnlcOtXiGP5FtTt6F6fthiC5a9kJE6E';

  var client = null;
  var ready = false;

  function init() {
    try {
      if (typeof window.supabase !== 'undefined' && window.supabase.createClient) {
        client = window.supabase.createClient(URL, ANON_KEY);
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
