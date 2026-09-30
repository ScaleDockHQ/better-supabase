import { createNext } from "better-supabase/next";

import { sb } from "./supabase";

export const next = createNext(sb, {
  debug: {
    ...(process.env["NEXT_E2E"] === "1" ? { enabled: true } : {}),
    budget: { calls: 8, waves: 2 },
  },
  // Applies when SUPABASE_READ_URL is set: reads stay on the primary this long after a write.
  replicas: { pinMs: 5000 },
});
