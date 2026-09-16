import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Calye Safe",
  description:
    "Barangay Calye incident reporting — resident, responder, and admin apps.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body style={{ margin: 0 }}>{children}</body>
    </html>
  );
}
