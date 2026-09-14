/**
 * Calye-Safe — data access layer
 *
 * Loads AFTER supabase-config.js. Every call tries Supabase first and
 * gracefully falls back to a localStorage cache / offline seed when the
 * database is unreachable, so the prototype keeps working offline.
 *
 * Usage:
 *   CalyeDB.isOnline()
 *   CalyeDB.fetch('reports', { order: 'created_at', asc: false, limit: 50 })
 *   CalyeDB.fetchOne('profiles', { id: '...' })
 *   CalyeDB.insert('reports', { ...row })
 *   CalyeDB.update('reports', { id: '...' }, { status: 'resolved' })
 *   CalyeDB.remove('reports', { id: '...' })
 *   CalyeDB.cached('announcements', cacheKey, () => Promise<rows>)
 *   CalyeDB.uploadStorage('evidence', 'proofs/asn-xxx.jpg', dataUrl) -> public URL
 */
window.CalyeDB = (function () {
  var cfg = window.CALYE_SUPABASE;

  function isOnline() {
    return cfg && cfg.isReady();
  }

  function client() {
    return cfg ? cfg.getClient() : null;
  }

  // ---- low-level helpers ---------------------------------------------------

  function buildQuery(table, opts) {
    var c = client();
    if (!c) return null;
    var q = c.from(table).select(opts.select || '*');
    if (opts.filters) {
      opts.filters.forEach(function (f) {
        var col = f[0], op = f[1], val = f[2];
        q = q[op](col, val);
      });
    }
    if (opts.order) q = q.order(opts.order, { ascending: !!opts.asc });
    if (opts.limit) q = q.limit(opts.limit);
    if (opts.range) q = q.range(opts.range[0], opts.range[1]);
    return q;
  }

  // ---- public API ----------------------------------------------------------

  function fetch(table, opts) {
    opts = opts || {};
    return new Promise(function (resolve) {
      var q = buildQuery(table, opts);
      if (!q) { resolve(null); return; }
      q.then(function (res) {
        if (res.error) { resolve(null); return; }
        resolve(res.data || []);
      }).catch(function () { resolve(null); });
    });
  }

  function fetchOne(table, filters) {
    return new Promise(function (resolve) {
      var q = buildQuery(table, { filters: filters, limit: 1 });
      if (!q) { resolve(null); return; }
      q.then(function (res) {
        if (res.error || !res.data || !res.data.length) { resolve(null); return; }
        resolve(res.data[0]);
      }).catch(function () { resolve(null); });
    });
  }

  function insert(table, rows) {
    var list = Array.isArray(rows) ? rows : [rows];
    return new Promise(function (resolve) {
      var c = client();
      if (!c) { resolve(null); return; }
      c.from(table).insert(list).select().then(function (res) {
        if (res.error) { resolve(null); return; }
        resolve(res.data || list);
      }).catch(function () { resolve(null); });
    });
  }

  // Normalize filters into [col, val] pairs. Accepts both:
  //   [['id', 1]]            (array of pairs)
  //   { id: 1 }              (plain object)
  function normalizeFilters(filters) {
    var pairs = [];
    if (!filters) return pairs;
    if (Array.isArray(filters)) {
      filters.forEach(function (f) { if (f && f.length >= 2) pairs.push([f[0], f[1]]); });
    } else if (typeof filters === 'object') {
      Object.keys(filters).forEach(function (k) { pairs.push([k, filters[k]]); });
    }
    return pairs;
  }

  function update(table, filters, patch) {
    return new Promise(function (resolve) {
      var c = client();
      if (!c) { resolve(null); return; }
      // .select() is required: without it PostgREST returns 204 with
      // data:null, which callers misread as failure (see decline flow).
      var q = c.from(table).update(patch).select();
      normalizeFilters(filters).forEach(function (f) {
        q = q.eq(f[0], f[1]);
      });
      q.then(function (res) {
        if (res.error) { resolve(null); return; }
        resolve(res.data);
      }).catch(function () { resolve(null); });
    });
  }

  function remove(table, filters) {
    return new Promise(function (resolve) {
      var c = client();
      if (!c) { resolve(null); return; }
      // .select() so callers can distinguish success (rows) from failure.
      var q = c.from(table).delete().select();
      normalizeFilters(filters).forEach(function (f) {
        q = q.eq(f[0], f[1]);
      });
      q.then(function (res) {
        if (res.error) { resolve(null); return; }
        resolve(res.data);
      }).catch(function () { resolve(null); });
    });
  }

  // ---- RPC (server-side functions, e.g. analytics aggregations) -------------

  function rpc(fn, params) {
    return new Promise(function (resolve) {
      var c = client();
      if (!c) { resolve(null); return; }
      c.rpc(fn, params || {}).then(function (res) {
        if (res.error) { resolve(null); return; }
        resolve(res.data);
      }).catch(function () { resolve(null); });
    });
  }

  // ---- storage (Supabase Storage buckets) -----------------------------------

  // Extract the object path from a public storage URL.
  // e.g. ".../object/public/verification-ids/<uid>/<ts>-id.png" -> "<uid>/<ts>-id.png"
  function bucketPath(bucket, url) {
    if (!url || !bucket) return '';
    var marker = '/object/public/' + bucket + '/';
    var i = url.indexOf(marker);
    if (i === -1) return '';
    return url.slice(i + marker.length);
  }

  // Generate a signed URL for a private-bucket object using the current
  // session (owner or staff). Returns '' on failure.
  function signedUrl(bucket, path, expiresIn) {
    return new Promise(function (resolve) {
      var c = client();
      if (!c || !path) { resolve(''); return; }
      c.storage.from(bucket).createSignedUrl(path, expiresIn || 3600).then(function (res) {
        if (res.error || !res.data || !res.data.signedUrl) { resolve(''); return; }
        resolve(res.data.signedUrl);
      }).catch(function () { resolve(''); });
    });
  }

  function dataUrlToBlob(dataUrl) {    try {
      var comma = dataUrl.indexOf(',');
      var head = dataUrl.slice(0, comma);
      var mime = (head.match(/data:([^;]+)/) || [])[1] || 'image/jpeg';
      var raw = atob(dataUrl.slice(comma + 1));
      var u8 = new Uint8Array(raw.length);
      for (var i = 0; i < raw.length; i++) u8[i] = raw.charCodeAt(i);
      return new Blob([u8], { type: mime });
    } catch (e) { return null; }
  }

  /**
   * uploadStorage(bucket, path, dataUrl):
   *   Uploads an image data URL to Supabase Storage and resolves with the
   *   public URL. Resolves null on any failure (caller decides fallback).
   */
  function uploadStorage(bucket, path, dataUrl) {
    return new Promise(function (resolve) {
      var c = client();
      if (!c || !c.storage || !dataUrl) { resolve(null); return; }
      var blob = dataUrlToBlob(dataUrl);
      if (!blob) { resolve(null); return; }
      c.storage.from(bucket).upload(path, blob, { contentType: blob.type || 'image/jpeg' })
        .then(function (res) {
          if (res.error || !res.data || !res.data.path) { resolve(null); return; }
          var pub = c.storage.from(bucket).getPublicUrl(res.data.path);
          resolve(pub && pub.data && pub.data.publicUrl ? pub.data.publicUrl : null);
        })
        .catch(function () { resolve(null); });
    });
  }

  // ---- localStorage cache with fallback ------------------------------------

  function lsGet(key) {
    try { return localStorage.getItem(key); } catch (e) { return null; }
  }

  function lsSet(key, val) {
    try { localStorage.setItem(key, val); } catch (e) { /* ignore */ }
  }

  /**
   * cached(key, fetchFn):
   *   - if online: run fetchFn(), save result to cache, return it.
   *   - if offline: return cached value, else run fetchFn().
   */
  function cached(key, fetchFn) {
    return new Promise(function (resolve) {
      if (isOnline()) {
        Promise.resolve(fetchFn()).then(function (data) {
          if (data && data !== null) {
            try { lsSet(key, JSON.stringify(data)); } catch (e) { /* ignore */ }
            resolve(data);
          } else {
            var old = lsGet(key);
            resolve(old ? safeParse(old) : null);
          }
        });
      } else {
        var cachedVal = lsGet(key);
        if (cachedVal) { resolve(safeParse(cachedVal)); return; }
        Promise.resolve(fetchFn()).then(resolve);
      }
    });
  }

  function safeParse(str) {
    try { return JSON.parse(str); } catch (e) { return null; }
  }

  function clearCache(prefix) {
    var re = new RegExp('^' + (prefix || 'calye_db_'));
    try {
      Object.keys(localStorage).forEach(function (k) {
        if (re.test(k)) localStorage.removeItem(k);
      });
    } catch (e) { /* ignore */ }
  }

  return {
    isOnline: isOnline,
    fetch: fetch,
    fetchOne: fetchOne,
    insert: insert,
    update: update,
    remove: remove,
    rpc: rpc,
    cached: cached,
    clearCache: clearCache,
    uploadStorage: uploadStorage,
    bucketPath: bucketPath,
    signedUrl: signedUrl
  };
})();
