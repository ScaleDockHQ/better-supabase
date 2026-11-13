import { tagFor } from "better-supabase/next";

/**
 * The key status read carries this tag, and the rotate action expires it
 * through `refreshCaller(auth, [ENCRYPTION_TAG])`.
 */
export const ENCRYPTION_TAG = tagFor("encryption");
