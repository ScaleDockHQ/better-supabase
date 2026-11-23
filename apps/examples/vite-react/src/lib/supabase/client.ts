import { createClient } from "better-supabase/client";

import { betterSupabase } from "./index";

export const bsb = createClient(betterSupabase, {
  env: {
    url: import.meta.env.VITE_SUPABASE_URL,
    publishableKey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
  },
  // Keeps the user object out of the session cookie; it lives in localStorage.
  cookies: { encode: "tokens-only" },
});
