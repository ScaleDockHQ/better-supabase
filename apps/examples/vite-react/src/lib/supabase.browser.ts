import { createBrowser } from "better-supabase/client";

import { sb } from "./supabase";

export const browser = createBrowser(sb, {
  env: {
    url: import.meta.env.VITE_SUPABASE_URL,
    publishableKey: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
  },
});
