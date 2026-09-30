import { defineBucket } from "better-supabase/storage";

import { buckets } from "./supabase/generated.ts";

/** `{orgId}/{customerId}/logo/{version}.webp`, readable within the tenant. */
export const logos = defineBucket(buckets.customerLogos);
