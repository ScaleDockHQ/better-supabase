import { tagFor } from "better-supabase/next";

/**
 * Every read of the jobs page carries this tag, and every write of its actions
 * expires it through `refreshCaller(auth, [JOBS_TAG])`.
 */
export const JOBS_TAG = tagFor("jobs");
