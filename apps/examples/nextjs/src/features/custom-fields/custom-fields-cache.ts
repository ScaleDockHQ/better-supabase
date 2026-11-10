import { tagFor } from "better-supabase/next";

/**
 * Every read of the custom-fields data carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [CUSTOM_FIELDS_TAG])`. A read
 * in another domain that shows the same rows carries it too.
 */
export const CUSTOM_FIELDS_TAG = tagFor("custom-fields");
