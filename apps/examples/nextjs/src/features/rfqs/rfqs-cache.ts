import { tagFor } from "better-supabase/next";

/**
 * Every read of the request pages carries this tag, and every write of
 * `rfqs-actions.ts` expires it through `refreshCaller(auth, [RFQS_TAG])`.
 */
export const RFQS_TAG = tagFor("rfqs");
