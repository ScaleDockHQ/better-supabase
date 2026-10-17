import type { BetterSupabaseContributions } from "better-supabase/server";

import type { Functions, Models } from "./lib/supabase/index.ts";

declare global {
  namespace Express {
    /** `toExpress` puts the `withBetterSupabase` contributions on `res.locals`. */
    // oxlint-disable-next-line typescript/no-empty-interface -- declaration merging needs an interface
    interface Locals extends BetterSupabaseContributions<
      Models,
      Functions,
      unknown
    > {}
  }
}
