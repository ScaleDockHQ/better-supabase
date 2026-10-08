import "server-only";
import { createNext, type NextOptions } from "better-supabase/next";

import { serverFetch } from "../latency";
import { betterSupabase } from "./index";

const options: NextOptions = {
  debug: {
    // The e2e build checks each navigation's budget against `next start`.
    enabled: process.env["EXPOSE_TESTING_API"] === "1",
    budget: { calls: 8, waves: 2 },
  },
  // Applies when SUPABASE_READ_URL is set: reads stay on the primary this long after a write.
  replicas: { pinMs: 5000 },
};

export const bs = createNext(
  betterSupabase,
  serverFetch
    ? { ...options, fetch: serverFetch, auth: { fetch: serverFetch } }
    : options,
);
