import type { BetterSupabaseContributions } from "better-supabase/server";

import type { Functions, Models } from "./lib/supabase/index.ts";

declare global {
  namespace Express {
    /** `toExpress` puts the `withBetterSupabase` contributions on `res.locals`. */
    interface Locals extends BetterSupabaseContributions<
      Models,
      Functions,
      unknown
    > {}
  }
}
