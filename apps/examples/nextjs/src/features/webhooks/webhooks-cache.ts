import { tagFor } from "better-supabase/next";

/**
 * Every read of the webhooks page carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [WEBHOOKS_TAG])`.
 */
export const WEBHOOKS_TAG = tagFor("webhooks");
