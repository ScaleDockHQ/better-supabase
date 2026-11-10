import { tagFor } from "better-supabase/next";

/**
 * Every read of the templates data carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [TEMPLATES_TAG])`. A read in
 * another domain that shows the same rows carries it too.
 */
export const TEMPLATES_TAG = tagFor("templates");
