import { createSupabase } from "better-supabase";
import "temporal-polyfill/global";
import { Temporal } from "temporal-polyfill";

import { toAppError } from "../app-error.ts";
import { avatars, logos } from "../buckets.ts";
import { Claims, Profile } from "../claims.ts";
import { schema } from "./generated-schema.ts";

export type { Functions, Models } from "./generated.ts";

/**
 * The server's app with every table, without its blocks. `index.ts` adds the
 * blocks (ADR 0232). The browser uses `client-app.ts`, which has no table
 * registry (ADR 0262).
 *
 * `.orThrow()` throws an `AppError`; results keep their `DbError`. `maxRows`
 * matches `[api] max_rows` in `supabase/config.toml`. Node 24 and Safari have
 * no `Temporal`, which the blocks return times as.
 */
export const app = createSupabase(schema, { maxRows: 1000, temporal: Temporal })
  .claims(Claims)
  .userMetadata(Profile)
  .mapError(toAppError)
  .buckets({ avatars, logos });
