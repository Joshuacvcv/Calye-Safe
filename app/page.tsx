import { redirect } from "next/navigation";

// Admin console only — the resident/responder apps ship as the APK,
// so the site root goes straight to the admin login.
export default function Home() {
  redirect("/app/calye-safe-admins.html");
}
