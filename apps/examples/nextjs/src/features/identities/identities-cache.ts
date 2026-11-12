import { tagFor } from "better-supabase/next";

/**
 * The caller's linked identities carry this tag; the actions expire it through
 * `refreshCaller(auth, [IDENTITIES_TAG])`.
 */
export const IDENTITIES_TAG = tagFor("identities");
