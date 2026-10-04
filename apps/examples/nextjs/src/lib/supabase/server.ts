import "server-only";
import { createNext } from "better-supabase/next";

import { betterSupabase } from "./index";

export const bs = createNext(betterSupabase, {
  debug: {
    budget: { calls: 8, waves: 2 },
  },
  // Applies when SUPABASE_READ_URL is set: reads stay on the primary this long after a write.
  replicas: { pinMs: 5000 },
});
