import type { ReactNode } from "react";

import AsyncStorage from "@react-native-async-storage/async-storage";
import NetInfo from "@react-native-community/netinfo";
import { createAsyncStoragePersister } from "@tanstack/query-async-storage-persister";
import {
  focusManager,
  onlineManager,
  QueryClient,
} from "@tanstack/react-query";
import { PersistQueryClientProvider } from "@tanstack/react-query-persist-client";
import {
  handleAuthDeepLink,
  syncQueryWithApp,
} from "better-supabase/client/native";
import { BetterSupabaseProvider } from "better-supabase/react";
import * as Linking from "expo-linking";
import { useEffect } from "react";
import { AppState } from "react-native";

import { bsb, supabase } from "../lib/supabase/client.native";
import { AuthGate } from "./auth-gate";

const DAY_MS = 24 * 60 * 60 * 1000;

const queryClient = new QueryClient({
  defaultOptions: { queries: { gcTime: DAY_MS } },
});

const queryPersister = createAsyncStoragePersister({
  storage: AsyncStorage,
  key: "bsb.query-cache",
});

/** IOS and Android: the client, the auth deep links and the sign-in gate. */
export function AppShell({ children }: { readonly children: ReactNode }) {
  useAuthLinks();
  useQuerySync();

  return (
    <PersistQueryClientProvider
      client={queryClient}
      persistOptions={{ persister: queryPersister, maxAge: DAY_MS }}
    >
      <BetterSupabaseProvider client={bsb}>
        <AuthGate>{children}</AuthGate>
      </BetterSupabaseProvider>
    </PersistQueryClientProvider>
  );
}

/** Refetch TanStack Query when the app is foreground or the network returns. */
function useQuerySync(): void {
  useEffect(
    () =>
      syncQueryWithApp({
        focusManager,
        onlineManager,
        appState: AppState,
        netInfo: NetInfo,
        supabase,
      }),
    [],
  );
}

/** Finishes magic-link and OAuth sign-ins that open the app. */
function useAuthLinks(): void {
  useEffect(() => {
    void Linking.getInitialURL().then((url) => {
      if (url) {
        void handleAuthDeepLink(supabase, url);
      }

      return url;
    });

    const subscription = Linking.addEventListener("url", ({ url }) => {
      void handleAuthDeepLink(supabase, url);
    });

    return () => {
      subscription.remove();
    };
  }, []);
}
