import { tagFor } from "better-supabase/next";

/**
 * Every marketplace read carries this tag, and `connectInstallation` expires it
 * through `refreshCaller(auth, [MARKETPLACE_TAG])`.
 */
export const MARKETPLACE_TAG = tagFor("marketplace");
