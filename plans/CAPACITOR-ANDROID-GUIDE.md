# Calye-Safe → Android (Capacitor) Migration Guide

Wraps the existing web apps (`calye-safe-community.html`, `calye-safe-responders.html`, `index.html`) into a real Android APK using Capacitor, with **no changes** to the app's HTML/JS logic.

## 0. Prerequisites (what you have / need)

| Tool | Status |
|------|--------|
| Node.js v24 | ✅ Installed |
| npm | ⚠️ Blocked by PowerShell (fix in Step 1) |
| Java JDK 17+ | ❌ Not installed (required by Android Gradle) |
| Android Studio | ✅ Installed (`C:\Program Files\Android\Android Studio`) |
| Android SDK | ✅ Found at `C:\Users\ASUS\AppData\Local\Android\Sdk` |

---

## Step 1 — Fix npm execution policy (one-time)

PowerShell refuses to run `npm.ps1`. Run once in an **Admin PowerShell**, or just use `npm.cmd` everywhere below:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
npm -v   # should print a version
```

---

## Step 2 — Install Java JDK 21 (Temurin)

1. Download: https://adoptium.net/temurin/releases/ → **Temurin 21 (LTS), Windows x64, .msi**
2. Install with default options (it sets `JAVA_HOME` automatically).
3. Verify in a **new** terminal:

```powershell
java -version
echo $env:JAVA_HOME
```

> Capacitor 7 requires JDK 21. If Gradle complains about the Java version (`invalid source release: 21`), you are on an older JDK — install Temurin 21 and point `JAVA_HOME` at it.

---

## Step 3 — Create the Capacitor project

Work in a new folder next to your project so the app code stays separate from the web code.

```powershell
cd C:\xampp\htdocs\Calye-Safe
mkdir calye-safe-android
cd calye-safe-android

npm.cmd init -y
npm.cmd install @capacitor/core @capacitor/cli @capacitor/android
npx cap init "Calye-Safe" "ph.atsu.calyesafe" --web-dir www
```

- `Calye-Safe` = app display name
- `ph.atsu.calyesafe` = unique package id (change to your real domain; once an APK is published it cannot be changed)

---

## Step 4 — Copy the web assets into `www/`

Capacitor serves `www/` as the app root. Copy the whole app **flat** (all siblings — the scripts are referenced with relative paths, so a flat copy keeps them working):

```powershell
Copy-Item ..\index.html          www\index.html
Copy-Item ..\calye-safe-community.html  www\
Copy-Item ..\calye-safe-responders.html www\
Copy-Item ..\calye-safe-admins.html     www\
Copy-Item ..\responder-login.html       www\
Copy-Item ..\supabase-config.js  www\
Copy-Item ..\supabase-data.js    www\
Copy-Item ..\supabase-auth.js     www\
Copy-Item ..\santarosa-boundary.js      www\
```

Verify nothing is missed:

```powershell
Get-ChildItem www | Select-Object Name
```

---

## Step 5 — (Recommended) Bundle the CDN libraries locally

Capacitor loads the app from `http://localhost` on the device, so CDNs *do* work — but bundling them makes the app load offline and avoids version drift. Download each dependency into `www/vendor/` and rewrite the `<script src>` / `<link href>` in the HTML files:

```powershell
New-Item -ItemType Directory -Path www\vendor
```

| Library | URL |
|---------|-----|
| leaflet.js | `https://unpkg.com/leaflet@1.9.4/dist/leaflet.js` |
| leaflet.css | `https://unpkg.com/leaflet@1.9.4/dist/leaflet.css` |
| leaflet-heat.js | `https://unpkg.com/leaflet.heat/dist/leaflet-heat.js` |
| leaflet-routing-machine.js | `https://unpkg.com/leaflet-routing-machine@3.2.12/dist/leaflet-routing-machine.js` |
| leaflet-routing-machine.css | `https://unpkg.com/leaflet-routing-machine@3.2.12/dist/leaflet-routing-machine.css` |
| supabase-js (UMD) | `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2` |

> For supabase-js, use the **UMD/CJS build** (`@supabase/supabase-js@2/dist/umd/supabase.js`) so `window.supabase` is defined — the app depends on that global (`supabase-config.js:19`).

Then in each HTML file change e.g.:
```html
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
```
to:
```html
<script src="vendor/leaflet.js"></script>
```
(Repeat for every CDN `<script>`/`<link>`. Fonts from Google Fonts can stay as-is.)

---

## Step 6 — Add the Android platform and permissions

```powershell
npx cap add android
npx cap sync
```

Add permissions to `android/app/src/main/AndroidManifest.xml` (inside `<manifest>`):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.CAMERA" />
```

- `INTERNET` exists by default — keep it.
- The app already requests location (`navigator.geolocation`, `calye-safe-community.html:3571`) and camera (`getUserMedia`, `:4521`) at runtime, so on Android 12+ users will be prompted with the native permission dialog automatically.

---

## Step 7 — Persist storage (optional but recommended)

`localStorage` works in the Capacitor WebView and survives restarts by default. If you want it to survive **app data clears / reinstalls**, migrate to Capacitor Preferences:

```powershell
npm.cmd install @capacitor/preferences
```

```js
// in supabase-data.js, replace localStorage.getItem/setItem with:
import { Preferences } from '@capacitor/preferences';
await Preferences.set({ key: key, value: JSON.stringify(data) });
const { value } = await Preferences.get({ key: key });
```

If you only ever test on a real device and never clear app data, you can skip this.

---

## Step 8 — Configure app display (optional)

In `capacitor.config.json` set the app name/icon/splash, then re-sync:

```json
{
  "appId": "ph.atsu.calyesafe",
  "appName": "Calye-Safe",
  "webDir": "www"
}
```

Icons/splash are generated later in Android Studio (or via `@capacitor/assets`).

---

## Step 9 — Build the APK

```powershell
npx cap sync
npx cap open android   # opens Android Studio
```

In Android Studio:
1. **Sync Gradle** (it will download Gradle + dependencies on first run — takes a few minutes).
2. **Build → Build Bundle(s)/APK(s) → Build APK(s)**.
3. APK output: `android\app\build\outputs\apk\debug\app-debug.apk`

Copy the APK to a phone, enable "Install from unknown sources", and test.

> **Debug vs release:** the debug APK is unsigned and fine for testing. For distribution you need a signed release build (Android Studio → Generate Signed Bundle). Note the current `supabase-config.js` uses the demo anon key with RLS disabled (`supabase-demo-access.sql`) — replace with real credentials + production RLS before any pilot (`GAPS-AND-SOLUTIONS.md`, Gap 8).

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `npm.ps1 cannot be loaded` | Use `npm.cmd` or run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| Gradle error about Java version | Install Temurin 17 and point `JAVA_HOME` at it |
| `Failed to find target Android 3x` | Android Studio → SDK Manager → install the platform + Build-Tools Gradle asks for |
| Camera/geolocation not prompting | Confirm the `<uses-permission>` lines in Step 6 were added, and that you're testing on a real device (emulator camera/location are limited) |
| Map tiles blank | Requires internet; confirm `INTERNET` permission and that the device has connectivity |
| `window.supabase` undefined | Your bundled supabase-js is the ESM build — switch to the UMD build (`dist/umd/supabase.js`) |
| CORS from Supabase | None — Supabase JS SDK talks to your Supabase host; keep the project's anon key |

---

## Timeline estimate

- Steps 1–2 (tooling): ~20–30 min (mostly the JDK download)
- Steps 3–6 (scaffold + copy + permissions): ~30 min
- Step 9 first build: ~10–20 min (Gradle download)
- **Total to a working APK: about 1–2 hours**, assuming your Supabase project is reachable.

---

## Option B — In-repo Capacitor (wired, no separate folder)

`capacitor.config.ts`, `scripts/build-www.js`, and the npm scripts are already in the repo root, so you can skip the separate `calye-safe-android` folder (Steps 3–4 above):

```powershell
cd C:\xampp\htdocs\Calye-Safe-main\Calye-Safe-main
npm.cmd install          # installs Next + Capacitor deps
npm.cmd run build:www    # copies the 9 allowlisted web files into www/
npx cap add android      # one-time: generates the android/ platform folder
npx cap sync
```

> Resident + responder apps only — `calye-safe-admins.html` is intentionally
> excluded from `www/` and the `/app` routes because the admin console
> stays web-only.

Then continue at Step 6 (permissions) and Step 9 (build APK) above. `www/` is gitignored and rebuilt every time via `npm.cmd run cap:sync`.
