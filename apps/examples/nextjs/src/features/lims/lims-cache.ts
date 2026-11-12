import { tagFor } from "better-supabase/next";

/**
 * Every read of the laboratory pages (samples, methods, results) carries this
 * tag, and every write of `lims-actions.ts` expires it through
 * `refreshCaller(auth, [LIMS_TAG])`.
 */
export const LIMS_TAG = tagFor("lims");
