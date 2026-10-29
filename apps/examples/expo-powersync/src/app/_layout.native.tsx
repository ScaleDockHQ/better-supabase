import { SessionProvider } from "better-supabase/react/native";
import { Stack } from "expo-router";
import { AppState } from "react-native";

import { AppShell } from "../components/app-shell";
import { sync } from "../lib/powersync/sync";

/**
 * IOS and Android. `<SessionProvider>` listens on `authz:<uid>` while the app
 * is in the foreground and catches up when it returns: a role change refreshes
 * the token, then reconnects PowerSync so the device drops the rows the user
 * lost.
 */
export default function RootLayout() {
  return (
    <AppShell>
      <SessionProvider appState={AppState} powersync={sync}>
        <Stack />
      </SessionProvider>
    </AppShell>
  );
}
