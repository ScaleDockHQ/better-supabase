import { createClient } from "better-supabase/client";

import { env } from "@/env";

import { blockConfig } from "./blocks.config";
import { clientApp } from "./client-app";

export const bsb = createClient(clientApp, {
  env: {
    url: env.NEXT_PUBLIC_SUPABASE_URL,
    publishableKey: env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  },
  blocks: blockConfig,
});
