import { tagFor } from "better-supabase/next";

/**
 * Every read of the content entries carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [CONTENT_TAG])`.
 */
export const CONTENT_TAG = tagFor("content_entries");
