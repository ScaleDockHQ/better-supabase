import { defineSupabase } from "better-supabase";

import { toAppError } from "../app-error.ts";
import { Claims, Profile } from "../claims.ts";
import { schema } from "./generated.ts";

export type { Functions, Models } from "./generated.ts";

/**
 * `.orThrow()` throws an `AppError`; results keep their `DbError`.
 * `maxRows` matches `[api] max_rows` in `supabase/config.toml`.
 */
export const betterSupabase = defineSupabase(schema, { maxRows: 1000 })
  .claims(Claims)
  .userMetadata(Profile)
  .mapError(toAppError);
