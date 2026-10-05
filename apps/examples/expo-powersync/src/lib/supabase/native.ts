import { createClient } from "@supabase/supabase-js";
import {
  createNativeClient,
  secureStorage,
} from "better-supabase/client/native";
import * as SecureStore from "expo-secure-store";

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

/** Writes go to PostgREST as the signed-in user, so RLS applies. */
export const bs = createNativeClient(betterSupabase, supabase);
