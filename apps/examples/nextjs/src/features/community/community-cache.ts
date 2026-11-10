import { tagFor } from "better-supabase/next";

/**
 * Every read of the community data carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [COMMUNITY_TAG])`. A read in
 * another domain that shows the same rows carries it too.
 */
export const COMMUNITY_TAG = tagFor("community");
