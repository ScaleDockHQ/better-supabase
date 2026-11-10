import { tagFor } from "better-supabase/next";

/**
 * Every read of the people data carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [PEOPLE_TAG])`. A read in
 * another domain that shows the same rows carries it too.
 */
export const PEOPLE_TAG = tagFor("people");
