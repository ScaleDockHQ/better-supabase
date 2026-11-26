import { tagFor } from "better-supabase/next";

/**
 * Every read of the change requests and their workflow carries this tag, and
 * every write of their actions expires it through `refreshCaller`.
 */
export const CHANGE_REQUESTS_TAG = tagFor("change_requests");
