import {
  createRateLimit as createRateLimitOf,
  rateLimited as rateLimitedOf,
} from "./rate-limit.ts";

/** @deprecated Import `createRateLimit` from `better-supabase/rate-limit`. */
export const createRateLimit: typeof createRateLimitOf = createRateLimitOf;

/** @deprecated Import `rateLimited` from `better-supabase/rate-limit`. */
export const rateLimited: typeof rateLimitedOf = rateLimitedOf;
