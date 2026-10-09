import type { ReactNode } from "react";

import { handleAuthDeepLink } from "better-supabase/client/native";
import { BetterSupabaseProvider } from "better-supabase/react";
import * as Linking from "expo-linking";
import { useEffect } from "react";

import { useSync } from "../lib/powersync/sync";
import { bs, supabase } from "../lib/supabase/native";
import { AuthGate } from "./auth-gate";

/** iOS and Android: the client, the auth deep links, sync and the sign-in gate. */
export function AppShell({ children }: { readonly children: ReactNode }) {
  useSync();
  useAuthLinks();
  return (
    <BetterSupabaseProvider client={bs}>
      <AuthGate>{children}</AuthGate>
    </BetterSupabaseProvider>
  );
}

/** Finishes magic-link and OAuth sign-ins that open the app. */
function useAuthLinks(): void {
  useEffect(() => {
    void Linking.getInitialURL().then((url) => {
      if (url) void handleAuthDeepLink(supabase, url);
    });
    const subscription = Linking.addEventListener("url", ({ url }) => {
      void handleAuthDeepLink(supabase, url);
    });
    return () => {
      subscription.remove();
    };
  }, []);
}
