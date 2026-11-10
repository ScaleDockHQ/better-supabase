import { tagFor } from "better-supabase/next";

/**
 * Every read of the privacy data carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [PRIVACY_TAG])`. A read in
 * another domain that shows the same rows carries it too.
 */
export const PRIVACY_TAG = tagFor("privacy");
