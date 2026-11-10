import { tagFor } from "better-supabase/next";

/**
 * Every read of the signing keys page carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [SIGNING_KEYS_TAG])`.
 */
export const SIGNING_KEYS_TAG = tagFor("signing_keys");
