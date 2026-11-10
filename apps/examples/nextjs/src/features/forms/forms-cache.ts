import { tagFor } from "better-supabase/next";

/**
 * Every read of the forms data carries this tag, and every write of its actions
 * expires it through `refreshCaller(auth, [FORMS_TAG])`. A read in another
 * domain that shows the same rows carries it too.
 */
export const FORMS_TAG = tagFor("forms");
