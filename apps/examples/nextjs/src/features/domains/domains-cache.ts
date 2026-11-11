import { tagFor } from "better-supabase/next";

/**
 * Every read of the domains page carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [DOMAINS_TAG])`.
 */
export const DOMAINS_TAG = tagFor("domains");
