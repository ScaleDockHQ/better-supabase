import { tagFor } from "better-supabase/next";

/**
 * Every read of the approvals data carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [APPROVALS_TAG])`. A read in
 * another domain that shows the same rows carries it too.
 */
export const APPROVALS_TAG = tagFor("approvals");
