import { defineSupabase } from "better-supabase";
import { Temporal } from "temporal-polyfill";

import { toAppError } from "../app-error.ts";
import { Claims, Profile } from "../claims.ts";
import { schema } from "./generated.ts";

export type { Functions, Models } from "./generated.ts";

/**
 * `.orThrow()` throws an `AppError`; results keep their `DbError`.
 * `maxRows` matches `[api] max_rows` in `supabase/config.toml`. Node 24 and
 * Safari have no `Temporal`, which the blocks return times as.
 */
export const betterSupabase = defineSupabase(schema, {
  maxRows: 1000,
  temporal: Temporal,
})
  .claims(Claims)
  .userMetadata(Profile)
  .mapError(toAppError);
