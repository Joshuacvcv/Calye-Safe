const LINKS: { href: string; title: string; desc: string }[] = [
  {
    href: "/app/index.html",
    title: "Resident Sign In",
    desc: "Login / register for Barangay Calye residents",
  },
  {
    href: "/app/calye-safe-community.html",
    title: "Community App",
    desc: "File and track incident reports",
  },
  {
    href: "/app/responder-login.html",
    title: "Responder Sign In",
    desc: "Login for Quick Response Team members",
  },
  {
    href: "/app/calye-safe-responders.html",
    title: "Responder App",
    desc: "Duty board, queue, and live job tracking",
  },
  {
    href: "/app/calye-safe-admins.html",
    title: "Admin Console",
    desc: "Reports, dispatch, analytics, and verification",
  },
];

export default function Home() {
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
      }}
    >
      <div style={{ width: "100%", maxWidth: 560 }}>
        <h1 style={{ color: "#fff", fontSize: 28, margin: "0 0 4px" }}>
          Calye Safe
        </h1>
        <p style={{ color: "rgba(255,255,255,0.7)", margin: "0 0 24px" }}>
          Choose an app to open
        </p>
        <div style={{ display: "grid", gap: 12 }}>
          {LINKS.map((l) => (
            <a
              key={l.href}
              href={l.href}
              style={{
                display: "block",
                background: "#fff",
                borderRadius: 12,
                padding: "14px 18px",
                textDecoration: "none",
                color: "#1E3A5F",
              }}
            >
              <div style={{ fontWeight: 700 }}>{l.title}</div>
              <div style={{ fontSize: 13, color: "#555" }}>{l.desc}</div>
            </a>
          ))}
        </div>
      </div>
    </main>
  );
}
