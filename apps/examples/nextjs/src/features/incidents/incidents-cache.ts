import { tagFor } from "better-supabase/next";

/**
 * Every read of the incident register carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [INCIDENTS_TAG])`.
 */
export const INCIDENTS_TAG = tagFor("incidents");
