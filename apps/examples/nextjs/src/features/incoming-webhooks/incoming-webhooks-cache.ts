import { tagFor } from "better-supabase/next";

/**
 * Every read of the incoming webhooks page carries this tag, and every write of
 * its actions expires it through `refreshCaller(auth,
 * [INCOMING_WEBHOOKS_TAG])`.
 */
export const INCOMING_WEBHOOKS_TAG = tagFor("incoming-webhooks");
