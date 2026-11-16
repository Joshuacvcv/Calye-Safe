// Generates barangay-boundaries.js
//
// Each barangay gets a service zone produced by a Voronoi (Thiessen)
// partition of the 18 barangay centre points, clipped to the official Santa
// Rosa city outline from santarosa-boundary.js. The cells therefore tile the
// city exactly: no gaps, no overlaps, and every border is shared by exactly
// the two barangays on either side of it.
//
// Real OSM boundary relations exist for only 4 of the 18 barangays
// (Pulong Santa Cruz, Malitlit, Don Jose, Santo Domingo — relations
// 7759873-7759876), so a mixed real/generated map was not possible; all 18
// are generated the same way instead.
//
// Centre points come from OpenStreetMap (Nominatim / Photon), matched
// against the canonical 18-name list used by index.html.
//
// Usage: node tools/generate-barangay-boundaries.js

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..');

// ── 1. City outline ──────────────────────────────────────────────────────────
const citySrc = fs.readFileSync(path.join(ROOT, 'santarosa-boundary.js'), 'utf8')
  + '\n;globalThis.__CITY = SANTA_ROSA_BOUNDARY;';
const ctx = {};
vm.runInNewContext(citySrc, ctx, { filename: 'santarosa-boundary.js' });
const CITY = ctx.__CITY;
if (!Array.isArray(CITY) || CITY.length < 3) throw new Error('city boundary missing');

// ── 2. Barangay centres (OpenStreetMap) ──────────────────────────────────────
const CENTERS = {
  'Aplaya':            [14.314444, 121.122508],
  'Balibago':          [14.296480, 121.105663],
  'Caingin':           [14.300950, 121.125459],
  'Dila':              [14.289847, 121.109587],
  'Dita':              [14.282607, 121.111139],
  'Don Jose':          [14.256257, 121.065966],
  'Ibaba':             [14.313514, 121.117151],
  'Kanluran':          [14.312715, 121.109138],
  'Labas':             [14.307920, 121.111216],
  'Macabling':         [14.306710, 121.101112],
  'Malitlit':          [14.267696, 121.111207],
  'Malusak':           [14.311783, 121.112372],
  'Market Area':       [14.319339, 121.112939],
  'Pook':              [14.302328, 121.108671],
  'Pulong Santa Cruz': [14.277622, 121.083503],
  'Santo Domingo':     [14.228413, 121.047922],
  'Sinalhan':          [14.332314, 121.106922],
  'Tagapo':            [14.313641, 121.100103]
};
const NAMES = Object.keys(CENTERS);

// ── 3. Geometry helpers ──────────────────────────────────────────────────────
function pointInPoly(lat, lng, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const xi = poly[i][0], yi = poly[i][1];
    const xj = poly[j][0], yj = poly[j][1];
    if (((yi > lng) !== (yj > lng)) &&
      (lat < (xj - xi) * (lng - yi) / (yj - yi) + xi)) inside = !inside;
  }
  return inside;
}

function signedArea(poly) {
  let a = 0;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    a += (poly[j][0] + poly[i][0]) * (poly[j][1] - poly[i][1]);
  }
  return a / 2;
}

// Sutherland–Hodgman: keep the half of `poly` that is at least as close to
// site `a` as to site `b` (i.e. clip by the perpendicular bisector).
function clipBisector(poly, a, b) {
  if (!poly.length) return poly;
  const nx = 2 * (b[0] - a[0]);
  const ny = 2 * (b[1] - a[1]);
  const c = (b[0] * b[0] + b[1] * b[1]) - (a[0] * a[0] + a[1] * a[1]);
  const out = [];
  const n = poly.length;
  for (let i = 0; i < n; i++) {
    const P = poly[i], Q = poly[(i + 1) % n];
    const dp = nx * P[0] + ny * P[1] - c;
    const dq = nx * Q[0] + ny * Q[1] - c;
    const pin = dp <= 0, qin = dq <= 0;
    if (pin) out.push(P);
    if (pin !== qin) {
      const t = dp / (dp - dq);
      out.push([P[0] + t * (Q[0] - P[0]), P[1] + t * (Q[1] - P[1])]);
    }
  }
  return out;
}

function centroid(poly) {
  let lat = 0, lng = 0;
  poly.forEach(p => { lat += p[0]; lng += p[1]; });
  return [lat / poly.length, lng / poly.length];
}

// ── 4. Keep every seed inside the city (a centre sitting on/beyond the border
//       would clip away to an empty cell) ────────────────────────────────────
const cityC = centroid(CITY);
const sites = {};
NAMES.forEach(n => {
  let p = CENTERS[n];
  if (pointInPoly(p[0], p[1], CITY)) { sites[n] = p; return; }
  for (let k = 1; k <= 200; k++) {
    const t = k / 200;
    const q = [p[0] + (cityC[0] - p[0]) * t, p[1] + (cityC[1] - p[1]) * t];
    if (pointInPoly(q[0], q[1], CITY)) { sites[n] = q; console.log('  nudged ' + n + ' inward'); return; }
  }
  throw new Error('could not place ' + n + ' inside the city');
});

// ── 5. Voronoi cells clipped to the city ─────────────────────────────────────
const cells = {};
NAMES.forEach(n => {
  let poly = CITY.map(p => [p[0], p[1]]);
  NAMES.forEach(m => {
    if (m === n) return;
    poly = clipBisector(poly, sites[n], sites[m]);
    if (!poly.length) return;
  });
  cells[n] = poly;
});

// ── 6. Validate ──────────────────────────────────────────────────────────────
const problems = [];
NAMES.forEach(n => {
  const cell = cells[n];
  if (!cell || cell.length < 3) { problems.push(n + ': degenerate cell (' + (cell ? cell.length : 0) + ' pts)'); return; }
  if (!pointInPoly(sites[n][0], sites[n][1], cell)) problems.push(n + ': own centre is outside its cell');
  if (Math.abs(signedArea(cell)) < 1e-9) problems.push(n + ': zero area');
});

// Every point of a dense grid that falls inside the city must land in
// exactly one cell (shared borders are a measure-zero case).
let multi = 0, none = 0, total = 0;
const lats = CITY.map(p => p[0]), lngs = CITY.map(p => p[1]);
const minLat = Math.min(...lats), maxLat = Math.max(...lats);
const minLng = Math.min(...lngs), maxLng = Math.max(...lngs);
for (let i = 1; i < 120; i++) {
  for (let j = 1; j < 120; j++) {
    const lat = minLat + (maxLat - minLat) * i / 120;
    const lng = minLng + (maxLng - minLng) * j / 120;
    if (!pointInPoly(lat, lng, CITY)) continue;
    total++;
    let hits = 0;
    NAMES.forEach(n => { if (pointInPoly(lat, lng, cells[n])) hits++; });
    if (hits === 0) none++;
    else if (hits > 1) multi++;
  }
}
console.log('grid points inside city: ' + total + '  uncovered: ' + none + '  overlapping: ' + multi);
if (none > total * 0.002) problems.push('coverage holes: ' + none);
if (multi > total * 0.002) problems.push('overlaps: ' + multi);
if (problems.length) {
  console.error('FAILED:\n  ' + problems.join('\n  '));
  process.exit(1);
}

// ── 7. Emit ──────────────────────────────────────────────────────────────────
const r6 = v => Math.round(v * 1e6) / 1e6;
const round = poly => poly.map(p => [r6(p[0]), r6(p[1])]);

const out = {};
const centers = {};
NAMES.forEach(n => {
  out[n] = round(cells[n]);
  centers[n] = [r6(sites[n][0]), r6(sites[n][1])];
});

const body = [
  '// Barangay service zones — Santa Rosa City, Laguna, Philippines',
  '//',
  '// GENERATED FILE — do not edit by hand. Regenerate with:',
  '//   node tools/generate-barangay-boundaries.js',
  '//',
  '// Each zone is a Voronoi (Thiessen) cell around the barangay centre point,',
  '// clipped to the official city outline in santarosa-boundary.js. The 18',
  '// cells tile the city exactly: no gaps, no overlaps, borders shared by',
  '// exactly the two barangays on either side.',
  '//',
  '// Centre points: OpenStreetMap (Nominatim / Photon). Real OSM boundary',
  '// relations exist for only 4 of the 18 barangays (Pulong Santa Cruz,',
  '// Malitlit, Don Jose, Santo Domingo), which is why all 18 are generated',
  '// the same way rather than mixing real and generated borders.',
  '//',
  '// Used for: drawBarangayBoundary(), isPointInBarangay(), barangayCenter()',
  '// and the "outside vicinity" check in calye-safe-admins.html.',
  '',
  'const BRGY_CENTERS = ' + JSON.stringify(centers) + ';',
  '',
  'const BRGY_BOUNDARIES = ' + JSON.stringify(out) + ';',
  '',
  'function barangayCenter(name) {',
  '  return BRGY_CENTERS[name] || null;',
  '}',
  '',
  'function barangayBounds(name) {',
  '  const poly = BRGY_BOUNDARIES[name];',
  '  if (!poly || !poly.length) return null;',
  '  let minLat = Infinity, minLng = Infinity, maxLat = -Infinity, maxLng = -Infinity;',
  '  poly.forEach(function (p) {',
  '    if (p[0] < minLat) minLat = p[0];',
  '    if (p[0] > maxLat) maxLat = p[0];',
  '    if (p[1] < minLng) minLng = p[1];',
  '    if (p[1] > maxLng) maxLng = p[1];',
  '  });',
  '  return [[minLat, minLng], [maxLat, maxLng]];',
  '}',
  '',
  '// Ray-casting point-in-polygon test against one barangay zone.',
  'function isPointInBarangay(lat, lng, name) {',
  '  const poly = BRGY_BOUNDARIES[name];',
  '  if (!poly || poly.length < 3) return true; // no zone → don\'t block',
  '  let inside = false;',
  '  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {',
  '    const xi = poly[i][0], yi = poly[i][1];',
  '    const xj = poly[j][0], yj = poly[j][1];',
  '    const intersect = ((yi > lng) !== (yj > lng)) &&',
  '      (lat < (xj - xi) * (lng - yi) / (yj - yi) + xi);',
  '    if (intersect) inside = !inside;',
  '  }',
  '  return inside;',
  '}',
  '',
  '// Draws one barangay border on a Leaflet map (same dashed look as the',
  '// city outline). Pass { all: true } on `name` to draw every zone at once.',
  'function drawBarangayBoundary(map, name, opts) {',
  '  if (!map || typeof L === "undefined") return null;',
  '  opts = opts || {};',
  '  const names = opts.all ? Object.keys(BRGY_BOUNDARIES) : (name ? [name] : []);',
  '  const layers = [];',
  '  names.forEach(function (n) {',
  '    const poly = BRGY_BOUNDARIES[n];',
  '    if (!poly || poly.length < 3) return;',
  '    layers.push(L.polygon(poly, {',
  '      color: opts.color || "#1E3A5F",',
  '      weight: opts.weight || 2,',
  '      opacity: opts.opacity || 0.9,',
  '      fill: opts.fill === true,',
  '      fillColor: opts.fillColor || opts.color || "#1E3A5F",',
  '      fillOpacity: opts.fillOpacity || 0.06,',
  '      dashArray: opts.dashArray || "6 6"',
  '    }).addTo(map).bindTooltip(n, { sticky: true, direction: "top" }));',
  '  });',
  '  return layers.length === 1 ? layers[0] : layers;',
  '}',
  ''
].join('\n');

const dest = path.join(ROOT, 'barangay-boundaries.js');
fs.writeFileSync(dest, body, 'utf8');
console.log('wrote ' + dest + ' (' + fs.statSync(dest).size + ' bytes)');
NAMES.forEach(n => console.log('  ' + n.padEnd(20) + cells[n].length + ' vertices'));
