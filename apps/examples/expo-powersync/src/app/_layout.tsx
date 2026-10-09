import { Stack } from "expo-router";

import { AppShell } from "../components/app-shell";

export default function RootLayout() {
  return (
    <AppShell>
      <Stack />
    </AppShell>
  );
}
