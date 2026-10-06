import { promises as fs } from "node:fs";
import path from "node:path";
import { NextResponse } from "next/server";

// Serves the existing static Calye Safe pages/assets under /app/* so the
// repo works as a Next.js app without moving or duplicating files.
// ADMIN CONSOLE ONLY — resident/responder apps are excluded on purpose
// (they ship as the APK). Strict allowlist: nothing else on disk
// (e.g. database backups) is served.
const PUBLIC_FILES: Record<string, string> = {
  "calye-safe-admins.html": "text/html; charset=utf-8",
  // Exception to admin-only: the password-reset page must be public so APK
  // users (whose origin is the app's private localhost) get a working link.
  "reset-password.html": "text/html; charset=utf-8",
  "supabase-config.js": "text/javascript; charset=utf-8",
  "supabase-auth.js": "text/javascript; charset=utf-8",
  "supabase-data.js": "text/javascript; charset=utf-8",
  "santarosa-boundary.js": "text/javascript; charset=utf-8",
  "calye-safe-logo.png": "image/png",
  "Santa Rosa Logo.png": "image/png",
};

export async function GET(
  _req: Request,
  { params }: { params: { path: string[] } },
) {
  const key = (params.path ?? []).join("/");
  const contentType = PUBLIC_FILES[key];
  if (!contentType) {
    return notFoundPage(key);
  }
  try {
    const data = await fs.readFile(path.join(process.cwd(), key));
    // HTML is never edge-cached: the console changes fast and operators
    // must always get the newest copy (stale admin HTML breaks layouts).
    // Versioned assets (logos, JS) stay cached for an hour.
    const cache = contentType.startsWith("text/html")
      ? "public, max-age=0, must-revalidate"
      : "public, max-age=3600";
    return new Response(data, {
      headers: {
        "Content-Type": contentType,
        "Cache-Control": cache,
      },
    });
  } catch {
    return notFoundPage(key);
  }
}

// Compact "Error 404" instead of a full error page — just the code,
// which path was requested, and a way back.
function notFoundPage(key: string) {
  const safe = key.replace(/[<>&"]/g, "");
  const html = `<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">`
    + `<meta name="viewport" content="width=device-width, initial-scale=1.0">`
    + `<title>Error 404 — Calye Safe</title>`
    + `<style>*{margin:0;padding:0;box-sizing:border-box}body{min-height:100vh;display:flex;align-items:center;justify-content:center;background:#1E3A5F;font-family:system-ui,-apple-system,sans-serif;padding:24px;color:#fff;text-align:center}</style>`
    + `</head><body><div><div style="font-size:64px;font-weight:800;">Error 404</div>`
    + `<p style="margin-top:8px;color:rgba(255,255,255,0.7);">Page not found: /app/${safe}</p>`
    + `<a href="/app/index.html" style="display:inline-block;margin-top:20px;background:#F5A623;color:#fff;font-weight:700;padding:12px 28px;border-radius:10px;text-decoration:none;">Back to Sign In</a>`
    + `</div></body></html>`;
  return new NextResponse(html, {
    status: 404,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}
