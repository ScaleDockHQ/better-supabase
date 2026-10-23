import { createClient } from "@supabase/supabase-js";
import { bindClient } from "better-supabase/client";
import {
  autoRefreshOnForeground,
  secureStorage,
} from "better-supabase/client/native";
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
 * PostgREST as the signed-in user, without the device database: the upload
 * connector replays local changes here, so RLS and validation run as they do
 * online.
 */
export const server = bindClient(betterSupabase, supabase);
