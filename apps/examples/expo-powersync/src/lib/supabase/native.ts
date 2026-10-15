import { createClient } from "@supabase/supabase-js";
import {
  autoRefreshOnForeground,
  createNativeClient,
  nativePorts,
  secureStorage,
} from "better-supabase/client/native";
import * as Linking from "expo-linking";
import * as Notifications from "expo-notifications";
import * as SecureStore from "expo-secure-store";
import { AppState } from "react-native";

import { betterSupabase } from ".";

export const supabase = createClient(
  process.env.EXPO_PUBLIC_SUPABASE_URL,
  process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  {
    auth: {
      storage: secureStorage(SecureStore),
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false,
    },
  },
);

// supabase-js can't tell when a React Native app is in the background.
autoRefreshOnForeground(supabase, AppState);

/**
 * Writes go to PostgREST as the signed-in user, so RLS applies. The ports
 * give the block hooks (`useNotifications` and the rest) their React Native
 * deep links, push token and uploads.
 */
export const bs = createNativeClient(betterSupabase, supabase, {
  ports: nativePorts({
    supabase,
    linking: Linking,
    notifications: Notifications,
    projectId: process.env.EXPO_PUBLIC_EAS_PROJECT_ID,
  }),
});
