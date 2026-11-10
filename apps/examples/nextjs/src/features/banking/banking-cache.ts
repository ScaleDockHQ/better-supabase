import { tagFor } from "better-supabase/next";

/**
 * Every read of the banking data carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [BANKING_TAG])`. A read in
 * another domain that shows the same rows carries it too.
 */
export const BANKING_TAG = tagFor("banking");
