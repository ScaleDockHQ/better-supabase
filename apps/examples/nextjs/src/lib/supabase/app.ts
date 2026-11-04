import { defineSupabase } from "better-supabase";
import { Temporal } from "temporal-polyfill";

import { toAppError } from "../app-error.ts";
import { avatars, logos } from "../buckets.ts";
import { Claims, Profile } from "../claims.ts";
import { schema } from "./generated.ts";

export type { Functions, Models } from "./generated.ts";

/**
 * The app without its blocks: what the browser client imports, so the block
 * manifests, their providers and the settings definitions stay out of client
 * bundles. `index.ts` adds the blocks on the server (ADR 0232).
 *
 * `.orThrow()` throws an `AppError`; results keep their `DbError`. `maxRows`
 * matches `[api] max_rows` in `supabase/config.toml`. Node 24 and Safari have
 * no `Temporal`, which the blocks return times as.
 */
export const app = defineSupabase(schema, { maxRows: 1000, temporal: Temporal })
  .claims(Claims)
  .userMetadata(Profile)
  .mapError(toAppError)
  .buckets({ avatars, logos });
