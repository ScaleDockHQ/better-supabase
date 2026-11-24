import { tagFor } from "better-supabase/next";

/**
 * Every server read of an API key carries this tag, and `rotateKey` expires it
 * through `refreshCaller(auth, [API_KEYS_TAG])`.
 */
export const API_KEYS_TAG = tagFor("api-keys");
