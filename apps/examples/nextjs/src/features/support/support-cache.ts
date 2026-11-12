import { tagFor } from "better-supabase/next";

/**
 * Every read of the support sessions carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [SUPPORT_TAG])`.
 */
export const SUPPORT_TAG = tagFor("support_sessions");
