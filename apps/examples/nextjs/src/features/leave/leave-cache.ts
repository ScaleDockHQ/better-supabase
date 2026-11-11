import { tagFor } from "better-supabase/next";

/** Every read of leave carries this tag; every leave action expires it. */
export const LEAVE_TAG = tagFor("leave");
