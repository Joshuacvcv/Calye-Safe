import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  // Change to your real domain before publishing — the appId cannot
  // be changed once an APK is published.
  appId: "ph.atsu.calyesafe",
  appName: "Calye Safe",
  webDir: "www",
  plugins: {
    SplashScreen: {
      launchShowDuration: 1200,
      launchAutoHide: true,
      backgroundColor: "#1E3A5F",
      showSpinner: false,
    },
  },
};

export default config;
