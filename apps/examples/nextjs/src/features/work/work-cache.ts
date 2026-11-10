import { tagFor } from "better-supabase/next";

/**
 * Every read of the work data carries this tag, and every write of its actions
 * expires it through `refreshCaller(auth, [WORK_TAG])`. A read in another
 * domain that shows the same rows carries it too.
 */
export const WORK_TAG = tagFor("work");
