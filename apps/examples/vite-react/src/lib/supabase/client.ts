import { createClient } from "better-supabase/client";

import { betterSupabase } from "./index";

export const bs = createClient(betterSupabase, {
  env: {
    url: import.meta.env.VITE_SUPABASE_URL,
    publishableKey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
  },
});
