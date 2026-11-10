import { tagFor } from "better-supabase/next";

/**
 * Every read of the cases data carries this tag, and every write of its actions
 * expires it through `refreshCaller(auth, [CASES_TAG])`. A read in another
 * domain that shows the same rows carries it too.
 */
export const CASES_TAG = tagFor("cases");
