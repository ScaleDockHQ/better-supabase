import { tagFor } from "better-supabase/next";

/** Every read of deadlines carries this tag; marking one done expires it. */
export const DEADLINES_TAG = tagFor("deadlines");
