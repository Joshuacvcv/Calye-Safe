'use strict';

/**
 * Calye-Safe — headless client-logic stress test.
 *
 * Loads the REAL app scripts (community / admin / responders) inside a mocked
 * browser (DOM, localStorage, Leaflet, Supabase client backed by an in-memory
 * database) and drives their functions at volume to catch exceptions and
 * measure throughput. It does NOT touch the live Supabase project.
 *
 * Usage:  node tests/stress-test.js [volume]
 *         volume defaults to 1200 reports.
 */

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..');
const VOLUME = parseInt(process.argv[2] || '1200', 10);

// ============================================================================
// 1. Browser mocks
// ============================================================================

function makeClassList() {
  const set = new Set();
  return {
    add: (...c) => c.forEach(x => set.add(x)),
    remove: (...c) => c.forEach(x => set.delete(x)),
    toggle: (c, force) => { if (force === true) set.add(c); else if (force === false) set.delete(c); else { if (set.has(c)) set.delete(c); else set.add(c); } return set.has(c); },
    contains: c => set.has(c)
  };
}

function makeElement(id) {
  return {
    id: id || '',
    value: '', textContent: '', innerHTML: '', src: '', alt: '', href: '', title: '',
    className: '',
    style: {}, dataset: {}, children: [], options: [], selectedIndex: -1,
    checked: false, disabled: false, files: [],
    classList: makeClassList(),
    appendChild(c) { this.children.push(c); this.__appendCount = (this.__appendCount || 0) + 1; return c; },
    removeChild(c) { this.children = this.children.filter(x => x !== c); return c; },
    insertBefore(c) { this.children.push(c); return c; },
    remove() {}, focus() {}, blur() {}, click() {}, scrollTo() {}, scrollIntoView() {},
    setAttribute() {}, removeAttribute() {}, getAttribute() { return null; },
    addEventListener() {}, removeEventListener() {},
    querySelector() { return makeElement(id + ':q'); },
    querySelectorAll() { return []; },
    closest() { return makeElement(id + ':c'); },
    matches() { return false; },
    getContext() {
      return {
        fillRect() {}, drawImage() {}, getImageData() { return { data: new Uint8ClampedArray(4) }; },
        putImageData() {}, createLinearGradient() { return { addColorStop() {} }; },
        canvas: { width: 0, height: 0 }
      };
    },
    play() { return Promise.resolve(); },
    pause() {}, load() {}, contains() { return false; }
  };
}

const els = new Map();
const documentMock = {
  body: makeElement('body'),
  documentElement: makeElement('documentElement'),
  title: '', hidden: false, visibilityState: 'visible', readyState: 'complete',
  getElementById(id) { if (!els.has(id)) els.set(id, makeElement(id)); return els.get(id); },
  querySelector(sel) { if (!els.has(sel)) els.set(sel, makeElement(sel)); return els.get(sel); },
  querySelectorAll() { return []; },
  createElement() { return makeElement('created'); },
  createElementNS() { return makeElement('createdNS'); },
  createTextNode() { return {}; },
  createDocumentFragment() { return { children: [], appendChild() {}, querySelector() { return makeElement('frag'); } }; },
  addEventListener() {}, removeEventListener() {},
  execCommand() { return false; }
};

const store = {};
const localStorageMock = {
  getItem(k) { return Object.prototype.hasOwnProperty.call(store, k) ? store[k] : null; },
  setItem(k, v) { store[k] = String(v); },
  removeItem(k) { delete store[k]; },
  clear() { Object.keys(store).forEach(k => delete store[k]); },
  key(i) { return Object.keys(store)[i] || null; },
  get length() { return Object.keys(store).length; }
};

const navigatorMock = {
  geolocation: {
    getCurrentPosition(s) { s && s({ coords: { latitude: 14.3122, longitude: 121.1114 } }); },
    watchPosition() { return 0; },
    clearWatch() {}
  },
  mediaDevices: { getUserMedia() { return Promise.reject(new Error('no camera in headless test')); } },
  clipboard: { writeText() { return Promise.resolve(); } },
  userAgent: 'calye-stress-test', onLine: true
};

function mapStub() {
  return {
    setView() { return this; }, addLayer() { return this; }, remove() { return this; }, off() { return this; },
    fitBounds() { return this; }, invalidateSize() { return this; }, flyTo() { return this; }, on() { return this; },
    removeLayer() { return this; }, eachLayer() {}, getBounds() { return { getNorthEast() { return { lat: 1, lng: 1 }; } }; },
    setMaxBounds() {}, removeControl() {}, addControl() {}, getCenter() { return { lat: 0, lng: 0 }; },
    getZoom() { return 15; }, panTo() {}
  };
}
function layerStub() {
  return {
    addTo() { return this; }, setUrl() {}, remove() {}, setLatLngs() { return this; }, setStyle() { return this; },
    setLatLng() { return this; }, setPopupContent() { return this; }, bindPopup() { return this; },
    on() { return this; }, getBounds() { return {}; }, openPopup() {}, setIcon() {}, setOpacity() {},
    bringToBack() {}, bringToFront() {}
  };
}
const LMock = {
  map: () => mapStub(),
  tileLayer: () => layerStub(),
  circleMarker: () => layerStub(),
  marker: () => layerStub(),
  polyline: () => layerStub(),
  polygon: () => layerStub(),
  latLng: (a, b) => ({ lat: a, lng: b }),
  latLngBounds: () => ({ extend() {}, getNorthEast() { return {}; }, getSouthWest() { return {}; } }),
  point: () => ({}),
  bounds: () => ({}),
  divIcon: (o) => o || {},
  icon: (o) => o || {},
  control: { zoom() { return { addTo() {} }; } },
  DomUtil: { setOpacity() {}, get() { return documentMock.createElement('div'); } },
  heatLayer: () => layerStub(),
  LayerGroup: function () { return layerStub(); },
  FeatureGroup: function () { return layerStub(); },
  extend: () => {}
};

// ============================================================================
// 2. Fake Supabase client (in-memory)
// ============================================================================

class FakeQuery {
  constructor(tables, table) {
    this.tables = tables;
    this.table = table;
    this.rows = (tables[table] || []).slice();
    this.mode = 'select';
    this.patch = null;
    this.insertRows = null;
    this.orderCol = null;
    this.orderAsc = true;
    this.limitN = Infinity;
    this.rangeN = null;
  }
  select() { return this; }
  eq(col, val) { this.rows = this.rows.filter(r => String(r[col]) === String(val)); return this; }
  in(col, vals) { const s = new Set(vals); this.rows = this.rows.filter(r => s.has(r[col])); return this; }
  gte(col, val) { this.rows = this.rows.filter(r => r[col] >= val); return this; }
  lte(col, val) { this.rows = this.rows.filter(r => r[col] <= val); return this; }
  order(col, opts) { this.orderCol = col; this.orderAsc = !(opts && opts.ascending === false); return this; }
  limit(n) { this.limitN = n; return this; }
  range(a, b) { this.rangeN = [a, b]; return this; }
  insert(list) {
    this.mode = 'insert';
    this.insertRows = (list || []).map(r => {
      const row = Object.assign({}, r);
      if (!row.id) row.id = 'id-' + Math.random().toString(36).slice(2, 10);
      return row;
    });
    return this;
  }
  update(patch) { this.mode = 'update'; this.patch = patch || {}; return this; }
  delete() { this.mode = 'delete'; return this; }
  then(cb) {
    let out;
    if (this.mode === 'insert') {
      this.tables[this.table] = this.tables[this.table] || [];
      this.insertRows.forEach(r => this.tables[this.table].push(r));
      out = this.insertRows;
    } else if (this.mode === 'update') {
      out = this.rows.map(r => Object.assign({}, r, this.patch));
      const byId = new Map(out.map(r => [r.id, r]));
      this.tables[this.table] = (this.tables[this.table] || []).map(r => byId.get(r.id) || r);
    } else if (this.mode === 'delete') {
      const ids = new Set(this.rows.map(r => r.id));
      this.tables[this.table] = (this.tables[this.table] || []).filter(r => !ids.has(r.id));
      out = this.rows;
    } else {
      out = this.rows;
      if (this.orderCol) {
        out = out.slice().sort((a, b) => {
          const av = a[this.orderCol], bv = b[this.orderCol];
          if (av == null) return 1;
          if (bv == null) return -1;
          return this.orderAsc ? (av > bv ? 1 : av < bv ? -1 : 0) : (av < bv ? 1 : av > bv ? -1 : 0);
        });
      }
      if (this.rangeN) out = out.slice(this.rangeN[0], this.rangeN[1] + 1);
      else if (out.length > this.limitN) out = out.slice(0, this.limitN);
    }
    const res = { error: null, data: out };
    if (typeof cb === 'function') {
      try {
        return Promise.resolve(cb(res));
      } catch (e) {
        return Promise.reject(e);
      }
    }
    return Promise.resolve(res);
  }
}

class FakeAuth {
  constructor(db) { this.db = db; this._session = null; }
  setSession(s) { this._session = s; }
  getSession() { return Promise.resolve({ error: null, data: { session: this._session } }); }
  signOut() { this._session = null; return Promise.resolve({ error: null }); }
  signUp() { return Promise.resolve({ error: null, data: { user: { id: 'u-new' }, session: { user: { id: 'u-new' } } } }); }
  signInWithPassword() { return Promise.resolve({ error: null, data: { user: { id: 'u-resident-1' }, session: { user: { id: 'u-resident-1' } } } }); }
}

class FakeStorage {
  from(bucket) {
    return {
      upload() { return Promise.resolve({ error: null, data: { path: 'x.jpg' } }); },
      getPublicUrl(p) { return { data: { publicUrl: 'https://fake.supabase.co/storage/v1/object/public/' + bucket + '/' + p } }; }
    };
  }
}

class FakeClient {
  constructor(db) {
    this.db = db;
    this.auth = new FakeAuth(db);
    this.storage = new FakeStorage();
  }
  from(t) { return new FakeQuery(this.db.tables, t); }
  rpc(fn, params) {
    const d = this.db.rpcs[fn];
    const data = d == null ? [] : (typeof d === 'function' ? d(params) : d);
    return Promise.resolve({ error: null, data: data });
  }
}

// ============================================================================
// 3. Seed data
// ============================================================================

function iso(ms) { return new Date(ms).toISOString(); }

function seedDB(n) {
  const now = Date.now();
  const tables = {
    reports: [],
    report_timeline: [],
    report_media: [],
    assignments: [],
    assignment_timeline: [],
    responders: [],
    profiles: [],
    announcements: [],
    map_incidents: [],
    hotlines: [],
    verification_requests: []
  };

  const cats = ['flood', 'hazard', 'garbage', 'crime', 'fire', 'accident', 'other'];
  for (let i = 1; i <= n; i++) {
    const created = now - i * 3600000;
    const status = i % 3 === 0 ? 'resolved' : (i % 3 === 1 ? 'responding' : 'pending');
    tables.reports.push({
      id: 'report-' + i,
      report_no: '#BRGY-TEST-' + i,
      reporter_id: i % 4 === 0 ? 'u-resident-1' : null,
      reporter_name: 'Resident ' + i,
      category: cats[i % cats.length],
      type: 'Stress Incident ' + i,
      severity: i % 5 === 0 ? 'major' : 'minor',
      priority: i % 3 === 0 ? 'resolved' : (i % 3 === 1 ? 'responding' : 'urgent'),
      description: 'Stress test report #' + i,
      location: 'Street ' + i + ', Purok ' + ((i % 4) + 1) + ', Barangay Calye',
      lat: 14.25 + ((i % 100) * 0.001),
      lng: 121.1 + ((i % 100) * 0.001),
      source: i % 2 === 0 ? 'resident' : 'BRGY',
      status: status,
      created_at: iso(created),
      updated_at: iso(created)
    });
    for (let s = 1; s <= 5; s++) {
      tables.report_timeline.push({
        id: 'tl-' + i + '-' + s,
        report_id: 'report-' + i,
        step: s,
        label: 'Step ' + s,
        note: '',
        happened_at: iso(created + s * 100000),
        state: s <= 2 ? 'done' : (s === 3 ? 'active' : 'pending')
      });
    }
    if (i % 2 === 0) {
      tables.report_media.push({
        id: 'media-' + i,
        report_id: 'report-' + i,
        kind: 'photo',
        url: 'https://fake.supabase.co/report-photo-' + i + '.jpg'
      });
    }
    if (i % 2 === 0) {
      const asnStatus = i % 3 === 0 ? 'resolved' : (i % 3 === 1 ? 'on_site' : 'assigned');
      const asnId = 'asn-' + i;
      tables.assignments.push({
        id: asnId,
        report_id: 'report-' + i,
        responder_id: i % 4 === 0 ? 'resp-1' : null,
        status: asnStatus,
        distance_km: 1.0,
        eta_min: 10,
        resolution_notes: asnStatus === 'resolved' ? 'Fixed during stress test' : '',
        proof_url: asnStatus === 'resolved' ? 'https://fake.supabase.co/proof-' + i + '.jpg' : null,
        assigned_at: iso(created + 900000),
        resolved_at: asnStatus === 'resolved' ? iso(created + 2 * 3600000) : null
      });
      for (let s = 1; s <= 5; s++) {
        tables.assignment_timeline.push({
          id: 'at-' + i + '-' + s,
          assignment_id: asnId,
          step: s,
          label: 'AT ' + s,
          happened_at: iso(created + s * 100000),
          state: s === 1 ? 'done' : (s === 2 ? 'done' : 'pending')
        });
      }
    }
    tables.map_incidents.push({
      id: 'pin-' + i,
      report_id: 'report-' + i,
      type: cats[i % cats.length],
      label: 'Stress Incident ' + i,
      location: 'Street ' + i + ', Purok ' + ((i % 4) + 1) + ', Barangay Calye',
      status: status,
      lat: 14.25 + ((i % 100) * 0.001),
      lng: 121.1 + ((i % 100) * 0.001),
      created_at: iso(created)
    });
  }

  tables.responders.push({
    id: 'resp-1', unit_id: 'RES-014', name: 'Resp One', vehicle: 'Patrol', agency: 'Barangay Calye QRT'
  });
  tables.profiles.push(
    { id: 'u-resident-1', role: 'resident', full_name: 'Res One', email: 'res@calye.ph', barangay: 'Barangay Calye', verification_status: 'approved', created_at: iso(now) },
    { id: 'u-resp-1', role: 'responder', full_name: 'Resp One', email: 'resp@calye.ph', unit_id: 'RES-014', shift: 'Day', sector: 'Purok 3', verification_status: 'approved', created_at: iso(now) }
  );
  tables.announcements.push(
    { id: 'ann-1', title: 'Stress advisory', body: 'Test', category: 'advisory', pushed: true, created_at: iso(now - 3600000) }
  );
  tables.hotlines.push(
    { id: 'hot-1', name: 'Barangay Hall', number: '1234', category: 'Barangay' }
  );
  tables.verification_requests.push(
    { id: 'vr-1', user_id: 'u-resident-1', role: 'resident', full_name: 'Res One', email: 'res@calye.ph', status: 'approved', submitted_at: iso(now - 7200000) }
  );

  const months = [];
  for (let i = 5; i >= 0; i--) {
    const d = new Date();
    d.setDate(1);
    d.setMonth(d.getMonth() - i);
    months.push({ label: d.toLocaleDateString('en-US', { month: 'short' }), count: 20 + i * 7 });
  }
  const rpcs = {
    fn_incident_summary: {
      totals: { total: n, open: Math.ceil(n * 2 / 3), resolved: Math.floor(n / 3) },
      by_category: [
        { category: 'crime', count: Math.ceil(n / 4), pct: 25 },
        { category: 'garbage', count: Math.ceil(n / 5), pct: 20 },
        { category: 'flood', count: Math.ceil(n / 10), pct: 10 }
      ],
      hotspots: [
        { location: 'Street 1, Purok 1, Barangay Calye', count: 12 },
        { location: 'Street 2, Purok 2, Barangay Calye', count: 9 }
      ],
      monthly: months,
      avg_resolution_hrs: 3.5
    },
    fn_monthly_summary: { total: 40, resolved: 30, by_category: [] }
  };

  return { tables: tables, rpcs: rpcs };
}

// ============================================================================
// 4. Context / app loader
// ============================================================================

function extractInlineScripts(htmlPath) {
  const html = fs.readFileSync(htmlPath, 'utf8');
  const out = [];
  const re = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi;
  let m;
  while ((m = re.exec(html)) !== null) out.push(m[1]);
  return out;
}

function makeSandbox(db) {
  const supabase = { createClient: () => new FakeClient(db) };
  const sandbox = {
    console: console,
    setTimeout: setTimeout, clearTimeout: clearTimeout, setInterval: setInterval, clearInterval: clearInterval,
    Promise: Promise, Date: Date, Math: Math, JSON: JSON, Object: Object, Array: Array,
    String: String, Number: Number, Boolean: Boolean, RegExp: RegExp, Map: Map, Set: Set, Symbol: Symbol,
    Error: Error, TypeError: TypeError, RangeError: RangeError,
    parseInt: parseInt, parseFloat: parseFloat, isNaN: isNaN,
    encodeURIComponent: encodeURIComponent, decodeURIComponent: decodeURIComponent,
    encodeURI: encodeURI, decodeURI: decodeURI,
    atob: atob, btoa: btoa, Blob: Blob, File: File,
    TextEncoder: TextEncoder, TextDecoder: TextDecoder,
    URL: URL, URLSearchParams: URLSearchParams, AbortController: AbortController,
    performance: performance, structuredClone: structuredClone,
    fetch: () => Promise.resolve({ json: () => Promise.resolve([]), ok: false }),
    requestAnimationFrame: () => 0, cancelAnimationFrame: () => {},
    getComputedStyle: () => ({ getPropertyValue: () => '' }),
    matchMedia: () => ({ matches: false, addListener() {}, removeListener() {} }),
    devicePixelRatio: 1,
    location: { href: 'https://localhost/', reload() {}, search: '' },
    navigator: navigatorMock,
    localStorage: localStorageMock,
    document: documentMock,
    L: LMock,
    supabase: supabase,
    window: null,
    self: null
  };
  sandbox.window = sandbox;
  sandbox.self = sandbox;
  sandbox.addEventListener = function () {};
  sandbox.removeEventListener = function () {};
  sandbox.dispatchEvent = function () {};
  sandbox.getSelection = function () { return { removeAllRanges() {} }; };
  sandbox.scrollTo = function () {};
  sandbox.scroll = function () {};
  sandbox.open = function () { return null; };
  sandbox.close = function () {};
  sandbox.parent = sandbox;
  sandbox.top = sandbox;
  sandbox.screen = { width: 1920, height: 1080, availWidth: 1920, availHeight: 1080 };
  sandbox.innerWidth = 1920;
  sandbox.innerHeight = 1080;
  sandbox.outerWidth = 1920;
  sandbox.outerHeight = 1080;
  return sandbox;
}

function makeDriver(opts) {
  const db = seedDB(opts.volume || VOLUME);
  const sandbox = makeSandbox(db);
  const ctx = vm.createContext(sandbox);
  const run = (code) => vm.runInContext(code, ctx, { filename: opts.name + '-inline.js' });

  // set session before app load so auth getStatus resolves with it
  if (opts.session) {
    db.tables.profiles = db.tables.profiles || [];
    db.client = new FakeClient(db);
    db.client.auth.setSession(opts.session);
    sandbox.supabase.createClient = () => db.client;
  }

  const files = [
    'supabase-config.js',
    'supabase-data.js',
    'supabase-auth.js',
    'santarosa-boundary.js'
  ];
  for (const f of files) {
    run(fs.readFileSync(path.join(ROOT, f), 'utf8'));
  }
  for (const script of extractInlineScripts(opts.html)) {
    run(script);
  }

  return {
    name: opts.name,
    run: run,
    runAsync: async (code) => {
      const r = run(code);
      if (r && typeof r.then === 'function') return await r;
      return r;
    },
    db: db
  };
}

// ============================================================================
// 5. Scenarios
// ============================================================================

async function communityDemoScenario(d) {
  return d.runAsync(`
(async function(){
  await new Promise(function(r){ setTimeout(r, 10); });
  // ready flag flips during load (CalyeAuth.init at bottom); sync again now
  syncFromSupabase();
  await new Promise(function(r){ setTimeout(r, 10); });
  await new Promise(function(r){ setTimeout(r, 10); });

  var filed = document.getElementById('stat-filed').textContent;
  var listHtml = document.getElementById('reports-list').innerHTML.length;

  var t0 = Date.now();
  for (var i = 0; i < 100; i++) { renderReports(); }
  var renderMs = Date.now() - t0;

  var openBefore = document.body.__appendCount || 0;
  for (var i = 2; i <= 50; i += 2) { openSubmittedPhoto('#BRGY-TEST-' + i); }
  for (var i = 6; i <= 48; i += 6) { openResolutionPhoto('#BRGY-TEST-' + i); }
  toggleTimeline('tl-BRGY-TEST-2');
  refreshCommunityStats();

  return {
    filed: filed,
    listHtml: listHtml,
    renderMs: renderMs,
    overlaysOpened: (document.body.__appendCount || 0) - openBefore,
    resolvedStat: document.getElementById('stat-resolved').textContent
  };
})()
`);
}

async function communityResidentScenario(d) {
  return d.runAsync(`
(async function(){
  await new Promise(function(r){ setTimeout(r, 10); });
  syncFromSupabase();
  await new Promise(function(r){ setTimeout(r, 10); });
  await new Promise(function(r){ setTimeout(r, 10); });
  return {
    filed: document.getElementById('stat-filed').textContent,
    listHtml: document.getElementById('reports-list').innerHTML.length,
    resolvedStat: document.getElementById('stat-resolved').textContent
  };
})()
`);
}

async function adminScenario(d) {
  return d.runAsync(`
(async function(){
  await new Promise(function(r){ setTimeout(r, 10); });
  await new Promise(function(r){ setTimeout(r, 10); });

  var dashTotal = document.getElementById('dash-total-reports').textContent;
  var dashResolved = document.getElementById('dash-resolved').textContent;
  var dashAvg = document.getElementById('dash-avg-response').textContent;
  var tableLen = document.getElementById('table-body').innerHTML.length;

  var t0 = Date.now();
  for (var i = 0; i < 300; i++) { renderTable(getFilteredData()); }
  var renderMs = Date.now() - t0;

  var t1 = Date.now();
  for (var i = 0; i < 150; i++) {
    filterTable('all', null);
    filterTable('responding', null);
    filterTable('resolved', null);
  }
  var filterMs = Date.now() - t1;

  // local-only resolve (no dbId) — currentDispatchDbId must be null
  document.getElementById('resolve-notes').value = 'local-only';
  openResolveModal('#BRGY-TEST-999', null);
  confirmResolve();
  await new Promise(function(r){ setTimeout(r, 0); });

  // batch resolve with dbIds
  var before = parseInt(document.getElementById('dash-resolved').textContent, 10) || 0;
  for (var i = 1; i <= 40; i++) {
    document.getElementById('resolve-notes').value = 'Stress resolved #' + i;
    openResolveModal('#BRGY-TEST-' + i, 'report-' + i);
    confirmResolve();
    await new Promise(function(r){ setTimeout(r, 0); });
  }
  var after = parseInt(document.getElementById('dash-resolved').textContent, 10) || 0;

  // dispatch batch
  for (var i = 1; i <= 5; i++) {
    document.getElementById('dispatch-notes').value = '';
    openResponseModal('#BRGY-TEST-' + i, 'report-' + i);
    confirmDispatch();
    await new Promise(function(r){ setTimeout(r, 0); });
  }

  // analytics
  loadAnalytics();
  await new Promise(function(r){ setTimeout(r, 10); });
  await new Promise(function(r){ setTimeout(r, 10); });
  var topZone = document.getElementById('an-top-zone').textContent;

  var t2 = Date.now();
  for (var i = 0; i < 200; i++) {
    var rows = [];
    for (var k = 0; k < 500; k++) {
      rows.push({ status: k % 3 === 0 ? 'resolved' : 'pending', severity: k % 5 === 0 ? 'major' : 'minor', category: ['crime','garbage','flood'][k % 3], location: 'Zone ' + (k % 20), created_at: new Date(Date.now() - k * 3600000).toISOString() });
    }
    computeAnalyticsSummary(rows);
  }
  var analyticsMs = Date.now() - t2;

  return {
    dashTotal: dashTotal,
    dashResolved: dashResolved,
    dashAvg: dashAvg,
    tableHtml: tableLen,
    renderMs: renderMs,
    filterMs: filterMs,
    resolvedBefore: before,
    resolvedAfter: after,
    topZone: topZone,
    analyticsMs: analyticsMs
  };
})()
`);
}

async function responderScenario(d) {
  return d.runAsync(`
(async function(){
  await new Promise(function(r){ setTimeout(r, 10); });
  await new Promise(function(r){ setTimeout(r, 10); });

  var queueHtml = document.getElementById('queue-list').innerHTML.length;
  var homeHtml = document.getElementById('home-queue-preview').innerHTML.length;

  var t0 = Date.now();
  for (var i = 0; i < 100; i++) { renderQueue(); }
  var queueMs = Date.now() - t0;

  var t1 = Date.now();
  var jobsRendered = 0;
  for (var i = 2; i <= 40; i += 2) {
    openJob('#BRGY-TEST-' + i);
    var len = document.getElementById('job-content').innerHTML.length;
    if (len > 0) jobsRendered++;
  }
  var jobMs = Date.now() - t1;

  // advance status on one active job (assigned -> en_route -> on_site)
  openJob('#BRGY-TEST-2');
  var advanced = 0;
  advanceStatus(); advanced++;
  advanceStatus(); advanced++;

  return {
    queueHtml: queueHtml,
    homeHtml: homeHtml,
    queueMs: queueMs,
    jobsRendered: jobsRendered,
    jobMs: jobMs,
    advanced: advanced
  };
})()
`);
}

// ============================================================================
// 6. Runner
// ============================================================================

const APP = {
  community: {
    html: path.join(ROOT, 'calye-safe-community.html'),
    name: 'community'
  },
  communityResident: {
    html: path.join(ROOT, 'calye-safe-community.html'),
    name: 'community-resident',
    session: { user: { id: 'u-resident-1' } }
  },
  admin: {
    html: path.join(ROOT, 'calye-safe-admins.html'),
    name: 'admin'
  },
  responders: {
    html: path.join(ROOT, 'calye-safe-responders.html'),
    name: 'responders',
    session: { user: { id: 'u-resp-1' } }
  }
};

async function main() {
  const results = [];
  const runApp = async (key, scenario, label) => {
    const app = APP[key];
    const driver = makeDriver(app);
    let errors = [];
    let metrics = null;
    const t = Date.now();
    try {
      metrics = await scenario(driver);
    } catch (e) {
      errors.push(label + ' crashed: ' + (e && e.stack ? e.stack.split('\n').slice(0, 4).join(' | ') : e));
    }
    const elapsed = Date.now() - t;
    results.push({ key: key, label: label, metrics: metrics, elapsedMs: elapsed, errors: errors });
  };

  console.log('Calye-Safe client-logic stress test');
  console.log('Volume: ' + VOLUME + ' reports seeded per app\n');

  // Community — demo mode (no session, all reports)
  await runApp('community', communityDemoScenario, 'My Reports (demo)');
  // Community — signed-in resident (filtered reports)
  await runApp('communityResident', communityResidentScenario, 'My Reports (resident)');
  // Admin
  await runApp('admin', adminScenario, 'Dashboard + resolve + analytics');
  // Responder
  await runApp('responders', responderScenario, 'Queue + job detail');

  console.log('=== RESULTS ===\n');
  let failed = 0;
  for (const r of results) {
    console.log('--- ' + r.label + ' (' + r.elapsedMs + 'ms) ---');
    if (r.errors.length) {
      failed += r.errors.length;
      r.errors.forEach(e => console.log('  [FAIL] ' + e));
      continue;
    }
    const m = r.metrics || {};
    Object.keys(m).forEach(k => console.log('  ' + k + ': ' + m[k]));
    console.log('  [OK] completed without exceptions');
    console.log('');
  }

  console.log(failed === 0 ? '\nALL SCENARIOS PASSED' : '\n' + failed + ' error(s) — see above');
  process.exit(failed === 0 ? 0 : 1);
}

if (require.main === module) {
  main().catch(e => {
    console.error('Harness failure:', e);
    process.exit(2);
  });
}

module.exports = { makeDriver, seedDB, APP, communityDemoScenario, communityResidentScenario, adminScenario, responderScenario, makeSandbox };
