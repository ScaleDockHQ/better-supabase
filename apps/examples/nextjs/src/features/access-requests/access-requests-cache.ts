import { tagFor } from "better-supabase/next";

/**
 * Every read of the access-requests data carries this tag, and every write of
 * its actions expires it through `refreshCaller(auth, [ACCESS_REQUESTS_TAG])`.
 * A read in another domain that shows the same rows carries it too.
 */
export const ACCESS_REQUESTS_TAG = tagFor("access-requests");
