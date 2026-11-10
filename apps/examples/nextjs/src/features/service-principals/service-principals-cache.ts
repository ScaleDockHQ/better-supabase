import { tagFor } from "better-supabase/next";

/**
 * Every read of the service-principals data carries this tag, and every write
 * of its actions expires it through `refreshCaller(auth,
 * [SERVICE_PRINCIPALS_TAG])`. A read in another domain that shows the same rows
 * carries it too.
 */
export const SERVICE_PRINCIPALS_TAG = tagFor("service-principals");
