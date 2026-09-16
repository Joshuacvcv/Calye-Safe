import { promises as fs } from "node:fs";
import path from "node:path";
import { NextResponse } from "next/server";

// Serves the existing static Calye Safe pages/assets under /app/* so the
// repo works as a Next.js app without moving or duplicating files.
// Resident + responder apps only — the admin console stays web-only.
// Strict allowlist: nothing else on disk (e.g. database backups) is served.
const PUBLIC_FILES: Record<string, string> = {
  "index.html": "text/html; charset=utf-8",
  "calye-safe-community.html": "text/html; charset=utf-8",
  "calye-safe-responders.html": "text/html; charset=utf-8",
  "responder-login.html": "text/html; charset=utf-8",
  "supabase-config.js": "text/javascript; charset=utf-8",
  "supabase-auth.js": "text/javascript; charset=utf-8",
  "supabase-data.js": "text/javascript; charset=utf-8",
  "santarosa-boundary.js": "text/javascript; charset=utf-8",
  "calye-safe-logo.png": "image/png",
};

export async function GET(
  _req: Request,
  { params }: { params: { path: string[] } },
) {
  const key = (params.path ?? []).join("/");
  const contentType = PUBLIC_FILES[key];
  if (!contentType) {
    return new NextResponse("Not found", { status: 404 });
  }
  try {
    const data = await fs.readFile(path.join(process.cwd(), key));
    return new Response(data, {
      headers: {
        "Content-Type": contentType,
        "Cache-Control": "public, max-age=3600",
      },
    });
  } catch {
    return new NextResponse("Not found", { status: 404 });
  }
}
