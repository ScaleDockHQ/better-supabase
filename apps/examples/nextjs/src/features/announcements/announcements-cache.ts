import { tagFor } from "better-supabase/next";

/**
 * Every read of the caller's announcements carries this tag, and dismissing one
 * expires it through `refreshCaller(auth, [ANNOUNCEMENTS_TAG])`.
 */
export const ANNOUNCEMENTS_TAG = tagFor("announcements");
