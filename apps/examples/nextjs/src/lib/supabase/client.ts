import { createClient } from "better-supabase/client";

import { env } from "@/env";

import { app } from "./app";
import { blockConfig } from "./blocks.config";

export const bsb = createClient(app, {
  env: {
    url: env.NEXT_PUBLIC_SUPABASE_URL,
    publishableKey: env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  },
  blocks: blockConfig,
});
