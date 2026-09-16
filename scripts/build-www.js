// Copies the static Calye Safe web files into www/ for Capacitor.
// Run: npm run build:www
// Keep this list in sync with app/app/[...path]/route.ts (same allowlist).
const fs = require("node:fs");
const path = require("node:path");

const FILES = [
  "index.html",
  "calye-safe-community.html",
  "calye-safe-admins.html",
  "calye-safe-responders.html",
  "responder-login.html",
  "supabase-config.js",
  "supabase-auth.js",
  "supabase-data.js",
  "santarosa-boundary.js",
  "calye-safe-logo.png",
];

const root = path.join(__dirname, "..");
const out = path.join(root, "www");
fs.mkdirSync(out, { recursive: true });

for (const f of FILES) {
  fs.copyFileSync(path.join(root, f), path.join(out, f));
  console.log("copied", f);
}
