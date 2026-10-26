import { createClient } from "better-supabase/client";

import { env } from "@/env";

import { blockConfig } from "./blocks.generated";
import { betterSupabase } from "./index";

export const bsb = createClient(betterSupabase, {
  env: {
    url: env.NEXT_PUBLIC_SUPABASE_URL,
    publishableKey: env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  },
  blocks: blockConfig,
});
