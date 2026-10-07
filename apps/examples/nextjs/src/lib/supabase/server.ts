import "server-only";
import { createNext } from "better-supabase/next";

import { betterSupabase } from "./index";

export const bs = createNext(betterSupabase, {
  debug: {
    // The e2e build checks each navigation's budget against `next start`.
    enabled: process.env["EXPOSE_TESTING_API"] === "1",
    budget: { calls: 8, waves: 2 },
  },
  // Applies when SUPABASE_READ_URL is set: reads stay on the primary this long after a write.
  replicas: { pinMs: 5000 },
});
