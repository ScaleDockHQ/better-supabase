import { tagFor } from "better-supabase/next";

/** Every read of the gifts carries this tag; the donation actions expire it. */
export const DONATIONS_TAG = tagFor("donations");
