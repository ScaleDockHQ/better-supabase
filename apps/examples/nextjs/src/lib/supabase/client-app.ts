import { createSupabase } from "better-supabase";

import { toAppError } from "../app-error.ts";
import { avatars, logos } from "../buckets.ts";
import { Claims, Profile } from "../claims.ts";
import { clientSchema } from "./generated.ts";

/**
 * The browser's app: `app.ts` without the server's tables. Each table registers
 * when a page uses it, through `bsb.table(...)` or a generated hook, so a page
 * ships the tables it imports and no others (ADR 0262). Keep its options in
 * step with `app.ts`. `Temporal` is the runtime's own; `TemporalGate` loads the
 * polyfill in browsers that have none (ADR 0005).
 */
export const clientApp = createSupabase(clientSchema, { maxRows: 1000 })
  .claims(Claims)
  .userMetadata(Profile)
  .mapError(toAppError)
  .buckets({ avatars, logos });
