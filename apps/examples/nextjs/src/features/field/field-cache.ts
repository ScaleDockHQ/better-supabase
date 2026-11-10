import { tagFor } from "better-supabase/next";

/**
 * Every read of the field data carries this tag, and every write of its actions
 * expires it through `refreshCaller(auth, [FIELD_TAG])`. A read in another
 * domain that shows the same rows carries it too.
 */
export const FIELD_TAG = tagFor("field");
