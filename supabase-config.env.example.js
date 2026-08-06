/**
 * Calye-Safe — deploy-time config template (NOT auto-loaded).
 *
 * Copy this file to `supabase-config.env.js`, fill in your project values,
 * and load it BEFORE supabase-config.js so the anon key / URL are not hard-
 * coded in committed files:
 *
 *   <script src="supabase-config.env.js"></script>
 *   <script src="supabase-config.js"></script>
 *
 * `supabase-config.env.js` is gitignored. This is a cleanliness nicety for a
 * static site — the anon key is still publicly readable in the browser and is
 * NOT a secret. The service_role key must never be placed here.
 */
window.CALYE_SUPABASE_ENV = {
  url: 'https://YOUR-PROJECT.supabase.co',
  anonKey: 'your-anon-publishable-key'
};