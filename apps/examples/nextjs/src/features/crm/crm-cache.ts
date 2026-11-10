import { tagFor } from "better-supabase/next";

/**
 * Every read of the crm data carries this tag, and every write of its actions
 * expires it through `refreshCaller(auth, [CRM_TAG])`. A read in another domain
 * that shows the same rows carries it too.
 */
export const CRM_TAG = tagFor("crm");
