import { tagFor } from "better-supabase/next";

/** Every read of the claims carries this tag; the warranty actions expire it. */
export const WARRANTY_TAG = tagFor("warranty");
