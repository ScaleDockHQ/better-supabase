import { tagFor } from "better-supabase/next";

/** Every read of the collections carries this tag; the actions expire it. */
export const COLLECTIONS_TAG = tagFor("collections");
