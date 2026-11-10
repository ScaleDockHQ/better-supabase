import { tagFor } from "better-supabase/next";

/**
 * Every read of the customers data carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [CUSTOMERS_TAG])`. A read in
 * another domain that shows the same rows carries it too.
 */
export const CUSTOMERS_TAG = tagFor("customers");
