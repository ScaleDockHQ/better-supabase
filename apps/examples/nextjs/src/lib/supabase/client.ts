import { createClient } from "better-supabase/client";

import { blockConfig } from "./blocks.generated";
import { betterSupabase } from "./index";

export const bs = createClient(betterSupabase, {
  env: {
    url: process.env.NEXT_PUBLIC_SUPABASE_URL!,
    publishableKey: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
  },
  blocks: blockConfig,
});
