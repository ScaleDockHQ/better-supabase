import { tagFor } from "better-supabase/next";

/** Every read of the reviews carries this tag; the review actions expire it. */
export const REVIEWS_TAG = tagFor("reviews");
