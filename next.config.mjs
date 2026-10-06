/** @type {import('next').NextConfig} */
const nextConfig = {
  async redirects() {
    return [
      { source: "/app", destination: "/app/calye-safe-admins.html", permanent: false },
    ];
  },
  // The /app route reads these loose files from disk at request time —
  // without this, Vercel's bundler leaves them out and every page 404s.
  experimental: {
    outputFileTracingIncludes: {
      "/app/*": [
        "./calye-safe-admins.html",
        "./reset-password.html",
        "./supabase-config.js",
        "./supabase-auth.js",
        "./supabase-data.js",
        "./santarosa-boundary.js",
        "./calye-safe-logo.png",
        "./Santa Rosa Logo.png",
      ],
    },
  },
};

export default nextConfig;
