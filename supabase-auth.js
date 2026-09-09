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

  function init(storageKey) {
    CALYE_SUPABASE.init(storageKey);
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
          // Persist the submitted details on the profile BEFORE resolving, so
          // a follow-up getStatus() (and the gate) sees the ID on file and
          // shows "under review" instead of asking for another upload.
          CalyeDB.update('profiles', [['id', user.id]], {
            full_name: row.full_name,
            email: row.email,
            address: row.address,
            barangay: opts.barangay || '',
            id_doc_url: row.id_doc_url,
            id_type: row.id_type,
            employment_info: row.employment_info,
            verification_status: 'pending'
          }).then(function () {
            resolve({ error: null, row: rows[0] });
          });
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
            // Session exists but the profile row is missing — most commonly an
            // account created before the on_auth_user_created trigger existed.
            // Recreate the pending profile from the session's metadata so the
            // gate can proceed to the ID-upload step. If the auth user itself
            // is gone server-side (insert fails its FK), clear the stale session.
            var meta = (session.user && session.user.user_metadata) || {};
            CalyeDB.insert('profiles', [{
              id: session.user.id,
              email: (session.user.email || '').toLowerCase(),
              full_name: meta.full_name || ((session.user.email || '').split('@')[0]) || '',
              role: meta.role === 'responder' ? 'responder' : 'resident',
              verification_status: 'pending'
            }]).then(function (rows) {
              if (!rows || !rows.length) {
                c.auth.signOut().then(function () {
                  resolve({ session: null, profile: null, status: null });
                });
                return;
              }
              resolve({
                session: session,
                profile: rows[0],
                status: 'pending'
              });
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

  // ── PASSWORD POLICY (applied across resident / responder / staff) ─────────
  // Core rules:
  //   1. Length — at least 8 required, 12+ recommended, 15+ for sensitive ops.
  //   2. Uniqueness — reject passwords that are widely reused (common/breached)
  //      or that mirror this account's own details (email, name).
  //   3. No common words / patterns — block "password", "123456", names,
  //      keyboard runs, repeated chars, sequential digits.
  //   4. No forced rotation — we intentionally do NOT force periodic resets;
  //      that is enforced by never expiring the session here.
  var COMMON_PASSWORDS = [
    'password', 'password1', 'password123', '123456', '1234567', '12345678',
    '123456789', '1234567890', '12345', '1234567890123456', 'qwerty', 'qwerty123',
    'qwertyuiop', 'abc123', 'abc12345', '123qwe', '123abc', 'iloveyou', '111111',
    '000000', '666666', '88888888', '654321', '012345', '123123', '121212',
    'a123456', 'a1234567', 'a123456789', 'aa123456', 'aaa111', 'passw0rd',
    'p@ssw0rd', 'admin', 'admin123', 'administrator', 'letmein', 'monkey',
    'monkey123', 'dragon', 'trustno1', 'master', 'shadow', 'sunshine', 'welcome',
    'welcome1', 'football', 'baseball', 'princess', 'dragon123', 'login', 'changeme',
    'secret', 'password!', 'guest', 'user', 'user123', 'test', 'test123',
    'hello123', 'rightnow', 'mustang', 'freedom', 'whatever', 'default',
    'yourpassword', 'access', 'linkedin', 'google', 'yahoo', 'michelle',
    'jordan', 'harley', 'jessica', 'superman', 'batman', 'pokemon', 'killer',
    'buster', 'soccer', 'diamond', 'starwars', 'charlie', 'dallas', 'tigger',
    'pepper', 'corona', 'zaq12wsx', '1q2w3e4r', '1qaz2wsx', 'qaz123', 'plm123'
  ];
  // Common weak building blocks used in pattern checks.
  var KEYBOARD_ROWS = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
  var SEQUENTIAL = '0123456789abcdefghijklmnopqrstuvwxyz';

  function containsRun(str, max) {
    // Detect a run of identical characters (e.g. "aaaaaa") or an ascending /
    // descending sequence of length >= 6 (e.g. "123456", "abcdef", "qazwsx").
    str = str.toLowerCase();
    var same = 1;
    for (var i = 1; i < str.length; i++) {
      if (str[i] === str[i - 1]) { same++; if (same >= max) return true; }
      else same = 1;
    }
    for (var j = 0; j < KEYBOARD_ROWS.length; j++) {
      if (str.indexOf(KEYBOARD_ROWS[j].substring(0, 5)) !== -1) return true;
    }
    for (var k = 0; k + 5 < str.length; k++) {
      var asc = true, desc = true;
      for (var s = 1; s < 5; s++) {
        var idx = SEQUENTIAL.indexOf(str[k + s - 1]);
        var nxt = SEQUENTIAL.indexOf(str[k + s]);
        if (idx === -1 || nxt === -1 || nxt !== idx + 1) asc = false;
        if (idx === -1 || nxt === -1 || nxt !== idx - 1) desc = false;
      }
      if (asc || desc) return true;
    }
    return false;
  }

  function tokensFor(opts) {
    var out = [];
    function push(s) {
      s = (s || '').toLowerCase().trim();
      if (s) out.push(s);
    }
    push(opts && opts.full_name);
    push(opts && opts.email);
    if (opts && opts.email) push((opts.email.split('@')[0] || '').replace(/[^a-z]/g, ''));
    if (opts && opts.email) { var host = (opts.email.split('@')[1] || '').split('.')[0]; push(host); }
    return out;
  }

  /**
   * Validate a candidate password against the Calye-Safe policy.
   * opts: { full_name, email } (used for personal-detail checks).
   * Returns { ok, message, strength } where strength is 0..4.
   */
  function evalPasswordPolicy(pw, opts) {
    opts = opts || {};
    var pass = (pw == null) ? '' : String(pw);
    if (!pass) return { ok: false, strength: 0, message: 'Password is required.' };
    if (pass.length < 8) {
      return { ok: false, strength: 0, message: 'Password must be at least 8 characters (12+ recommended, 15+ for sensitive roles).' };
    }
    var lower = pass.toLowerCase();
    // Reused / common passwords.
    if (COMMON_PASSWORDS.indexOf(lower) !== -1 || COMMON_PASSWORDS.indexOf(lower.replace(/[^a-z0-9]/g, '')) !== -1) {
      return { ok: false, strength: 1, message: 'This password is too common and widely used. Choose a unique one.' };
    }
    // Personal details (email, name) — prevents password mirrors the account.
    var tokens = tokensFor(opts);
    for (var t = 0; t < tokens.length; t++) {
      if (tokens[t].length >= 3 && lower.indexOf(tokens[t]) !== -1) {
        return { ok: false, strength: 1, message: 'Password cannot contain your name or email address.' };
      }
    }
    // Weak patterns: repeated / sequential / keyboard runs.
    if (containsRun(lower, 4)) {
      return { ok: false, strength: 1, message: 'Password is too repetitive or uses an obvious sequence (e.g. "123456", "aaaa").' };
    }
    var strength = 2;
    if (pass.length >= 12) strength = 3;
    if (pass.length >= 15 && /[A-Z]/.test(pass) && /[0-9]/.test(pass) && /[^A-Za-z0-9]/.test(pass)) strength = 4;
    return { ok: true, strength: strength };
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
    getStatus: getStatus,
    passwordPolicy: evalPasswordPolicy
  };
})();
