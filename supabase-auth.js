/**
 * Calye-Safe — auth + verification library
 *
 * Load AFTER supabase-config.js and supabase-data.js (supabase-js CDN too).
 *
 *   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
 *   <script src="supabase-config.js"></script>
 *   <script src="supabase-data.js"></script>
 *   <script src="supabase-auth.js"></script>
 *
 * Roles: 'resident' | 'responder' | 'staff' | 'admin'
 * Sign-up always creates a 'pending' profile. The admin approves/rejects it
 * from the Verify Users queue. Apps must gate on CalyeAuth.getStatus().
 */
window.CalyeAuth = (function () {
  var client = null;
  var lastSession = null;

  function init() {
    CALYE_SUPABASE.init();
    client = CALYE_SUPABASE.getClient();
    return !!client;
  }

  function getClient() {
    if (!client) init();
    return client;
  }

  function isOnline() {
    return CALYE_SUPABASE.isReady();
  }

  /**
   * Get the current session (sync snapshot if we already fetched it,
   * otherwise a promise).
   */
  function currentSession() {
    return new Promise(function (resolve) {
      var c = getClient();
      if (!c) { resolve(null); return; }
      c.auth.getSession().then(function (res) {
        lastSession = res.data && res.data.session ? res.data.session : null;
        resolve(lastSession);
      }).catch(function () { resolve(null); });
    });
  }

  /**
   * Sign up a resident or responder.
   * Creates the auth user with metadata so the DB trigger can set the role.
   * Returns { error, session, user }.
   */
  function signUp(opts) {
    return new Promise(function (resolve) {
      var c = getClient();
      if (!c) { resolve({ error: 'Database not reachable' }); return; }
      var meta = {
        role: opts.role || 'resident',
        full_name: opts.full_name || ''
      };
      c.auth.signUp({
        email: opts.email,
        password: opts.password,
        options: { data: meta }
      }).then(function (res) {
        if (res.error) { resolve({ error: res.error.message }); return; }
        var user = res.data && res.data.user ? res.data.user : null;
        var session = res.data && res.data.session ? res.data.session : null;
        lastSession = session;
        resolve({ session: session, user: user, error: null });
      }).catch(function (e) { resolve({ error: e.message || 'Sign-up failed' }); });
    });
  }

  /**
   * Email + password sign in. Returns { error, session, user }.
   */
  function signIn(email, password) {
    return new Promise(function (resolve) {
      var c = getClient();
      if (!c) { resolve({ error: 'Database not reachable' }); return; }
      c.auth.signInWithPassword({ email: email, password: password })
        .then(function (res) {
          if (res.error) { resolve({ error: res.error.message }); return; }
          var session = res.data && res.data.session ? res.data.session : null;
          var user = res.data && res.data.user ? res.data.user : null;
          lastSession = session;
          resolve({ session: session, user: user, error: null });
        }).catch(function (e) { resolve({ error: e.message || 'Sign-in failed' }); });
    });
  }

  /**
   * Sign out. Returns a promise resolving to true on success.
   */
  function signOut() {
    return new Promise(function (resolve) {
      var c = getClient();
      if (!c) { resolve(true); return; }
      c.auth.signOut().then(function () { resolve(true); })
        .catch(function () { resolve(true); });
    });
  }

  /**
   * Upload a valid-ID photo into the 'verification-ids' bucket.
   * Path: {userId}/{timestamp}-{sanitized filename}
   * Returns { error, path, url }.
   */
  function uploadId(file) {
    return new Promise(function (resolve) {
      var c = getClient();
      if (!c) { resolve({ error: 'Database not reachable' }); return; }
      c.auth.getSession().then(function (sres) {
        var user = sres.data && sres.data.session ? sres.data.session.user : null;
        if (!user) { resolve({ error: 'You must be signed in to upload an ID' }); return; }
        var ext = (file.name || '').split('.').pop().toLowerCase();
        if (['jpg', 'jpeg', 'png', 'webp'].indexOf(ext) === -1) {
          resolve({ error: 'Please upload a JPG, PNG or WebP image.' });
          return;
        }
        var path = user.id + '/' + Date.now() + '-id.' + ext;
        c.storage.from('verification-ids').upload(path, file, {
          upsert: true
        }).then(function (up) {
          if (up.error) { resolve({ error: up.error.message }); return; }
          var url = c.storage.from('verification-ids').getPublicUrl(path).data.publicUrl;
          resolve({ error: null, path: path, url: url });
        }).catch(function (e) { resolve({ error: e.message || 'Upload failed' }); });
      });
    });
  }

  /**
   * Submit (or resubmit) a verification request with the uploaded ID.
   * Inserts a row into verification_requests and updates the profile.
   * opts: { role, full_name, email, address, employment_info, id_doc_url, id_type }
   * Returns { error, row }.
   */
  function submitVerification(opts) {
    return new Promise(function (resolve) {
      var c = getClient();
      if (!c) { resolve({ error: 'Database not reachable' }); return; }
      c.auth.getSession().then(function (sres) {
        var user = sres.data && sres.data.session ? sres.data.session.user : null;
        if (!user) { resolve({ error: 'You must be signed in' }); return; }
        var row = {
          user_id: user.id,
          role: opts.role || 'resident',
          full_name: opts.full_name || '',
          email: opts.email || '',
          address: opts.address || '',
          employment_info: opts.employment_info || null,
          id_doc_url: opts.id_doc_url || '',
          id_type: opts.id_type || '',
          status: 'pending',
          submitted_at: new Date().toISOString(),
          reviewed_at: null,
          review_note: ''
        };
        CalyeDB.insert('verification_requests', [row]).then(function (rows) {
          if (!rows || !rows.length) { resolve({ error: 'Could not save your verification request' }); return; }
          CalyeDB.update('profiles', [['id', user.id]], {
            full_name: row.full_name,
            email: row.email,
            address: row.address,
            id_doc_url: row.id_doc_url,
            id_type: row.id_type,
            employment_info: row.employment_info,
            verification_status: 'pending'
          });
          resolve({ error: null, row: rows[0] });
        });
      });
    });
  }

  /**
   * Current user's profile + verification status.
   * Returns Promise<{ session, profile, status }> where status is
   * 'pending' | 'approved' | 'rejected' | null (signed out).
   */
  function getStatus() {
    return new Promise(function (resolve) {
      var c = getClient();
      if (!c) { resolve({ session: null, profile: null, status: null }); return; }
      c.auth.getSession().then(function (sres) {
        var session = sres.data && sres.data.session ? sres.data.session : null;
        if (!session) { resolve({ session: null, profile: null, status: null }); return; }
        CalyeDB.fetchOne('profiles', [['id', 'eq', session.user.id]]).then(function (profile) {
          if (!profile) {
            // Session exists but the account was deleted server-side
            // (or the profile row is missing) — clear the stale session.
            c.auth.signOut().then(function () {
              resolve({ session: null, profile: null, status: null });
            });
            return;
          }
          resolve({
            session: session,
            profile: profile,
            status: profile ? (profile.verification_status || 'pending') : 'pending'
          });
        });
      }).catch(function () { resolve({ session: null, profile: null, status: null }); });
    });
  }

  return {
    init: init,
    isOnline: isOnline,
    currentSession: currentSession,
    signUp: signUp,
    signIn: signIn,
    signOut: signOut,
    uploadId: uploadId,
    submitVerification: submitVerification,
    getStatus: getStatus
  };
})();
