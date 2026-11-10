import { tagFor } from "better-supabase/next";

/**
 * Every read of the sso page carries this tag, and every write of its actions
 * expires it through `refreshCaller(auth, [SSO_TAG])`.
 */
export const SSO_TAG = tagFor("sso");
