import { tagFor } from "better-supabase/next";

/**
 * Every read of the rules data carries this tag, and every write of its actions
 * expires it through `refreshCaller(auth, [RULES_TAG])`. A read in another
 * domain that shows the same rows carries it too.
 */
export const RULES_TAG = tagFor("rules");
