import { createEnv } from "@t3-oss/env-nextjs";
import * as v from "valibot";

/**
 * The keys a Client Component may read. `createEnv` ships its whole schema to
 * the browser, so the server keys live in `env.ts`, which extends this one;
 * browser code imports `@/env-public`.
 */
export const publicEnv = createEnv({
  client: {
    NEXT_PUBLIC_SUPABASE_URL: v.pipe(v.string(), v.url()),
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: v.pipe(v.string(), v.minLength(1)),
    // The VAPID public key for web push; the push card hides without it.
    NEXT_PUBLIC_VAPID_PUBLIC_KEY: v.optional(v.string()),
  },
  runtimeEnv: {
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:
      process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    NEXT_PUBLIC_VAPID_PUBLIC_KEY: process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY,
  },
  emptyStringAsUndefined: true,
});
