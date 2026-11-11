import { tagFor } from "better-supabase/next";

/**
 * Every read of the asset register carries this tag, and every write of its
 * actions expires it through `refreshCaller(auth, [ASSETS_TAG])`.
 */
export const ASSETS_TAG = tagFor("assets");
