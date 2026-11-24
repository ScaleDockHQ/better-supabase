import { tagFor } from "better-supabase/next";

/**
 * Every read of a prescription carries this tag, and every write of its actions
 * expires it through `refreshCaller(auth, [PRESCRIPTIONS_TAG])`.
 */
export const PRESCRIPTIONS_TAG = tagFor("prescriptions");
