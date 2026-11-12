import { tagFor } from "better-supabase/next";

/**
 * Every read of the moderation queue and the bans carries this tag, and every
 * write of its actions expires it through `refreshCaller`.
 */
export const MODERATION_TAG = tagFor("moderation");
