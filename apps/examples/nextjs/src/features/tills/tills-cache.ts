import { tagFor } from "better-supabase/next";

/**
 * Every read of the till pages (tills, sessions, movements, counts, deposits)
 * carries this tag, and every write of `tills-actions.ts` expires it through
 * `refreshCaller(auth, [TILLS_TAG])`.
 */
export const TILLS_TAG = tagFor("tills");

/** The tags a till write expires. */
export const TILLS_CACHE_TAGS = [TILLS_TAG];
