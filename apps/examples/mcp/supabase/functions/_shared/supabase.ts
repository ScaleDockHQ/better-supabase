import { createSupabase } from "better-supabase";
import * as v from "valibot";

import { schema } from "../../../lib/supabase/generated-schema.ts";

/**
 * The custom access token hook sets `user_role` to one role or a list. A token
 * without it reads as no role instead of failing validation.
 */
const RoleClaims = v.looseObject({
  user_role: v.fallback(
    v.optional(v.union([v.string(), v.array(v.string())])),
    undefined,
  ),
});

export const betterSupabase = createSupabase(schema).claims(RoleClaims);
