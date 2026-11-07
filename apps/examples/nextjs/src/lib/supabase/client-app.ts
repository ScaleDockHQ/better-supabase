import { createSupabase } from "better-supabase";
import { Temporal } from "temporal-polyfill";

import { toAppError } from "../app-error.ts";
import { avatars, logos } from "../buckets.ts";
import { Claims, Profile } from "../claims.ts";
import { clientSchema } from "./generated.ts";

/**
 * The browser's app: `app.ts` without the server's tables. Each table registers
 * when a page uses it, through `bsb.table(...)` or a generated hook, so a page
 * ships the tables it imports and no others (ADR 0262). Keep its options in
 * step with `app.ts`.
 */
export const clientApp = createSupabase(clientSchema, {
  maxRows: 1000,
  temporal: Temporal,
})
  .claims(Claims)
  .userMetadata(Profile)
  .mapError(toAppError)
  .buckets({ avatars, logos });
