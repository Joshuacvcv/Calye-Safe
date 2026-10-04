import Link from "next/link";

// Compact "Error 404" instead of a full error page.
export default function NotFound() {
  return (
    <main
      style={{
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: "#1E3A5F",
        fontFamily: "system-ui, -apple-system, sans-serif",
        padding: 24,
        color: "#fff",
        textAlign: "center",
      }}
    >
      <div>
        <div style={{ fontSize: 64, fontWeight: 800 }}>Error 404</div>
        <p style={{ marginTop: 8, color: "rgba(255,255,255,0.7)" }}>
          This page doesn&apos;t exist or was moved.
        </p>
        <Link
          href="/app/index.html"
          style={{
            display: "inline-block",
            marginTop: 20,
            background: "#F5A623",
            color: "#fff",
            fontWeight: 700,
            padding: "12px 28px",
            borderRadius: 10,
            textDecoration: "none",
          }}
        >
          Back to Sign In
        </Link>
      </div>
    </main>
  );
}
