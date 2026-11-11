import { tagFor } from "better-supabase/next";

/** Every read of the passes carries this tag; the pass actions expire it. */
export const PASSES_TAG = tagFor("passes");
