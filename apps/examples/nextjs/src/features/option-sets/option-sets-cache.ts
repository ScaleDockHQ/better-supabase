import { tagFor } from "better-supabase/next";

/**
 * Every read of the option sets pages carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [OPTION_SETS_TAG])`.
 */
export const OPTION_SETS_TAG = tagFor("option-sets");
