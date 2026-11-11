import { tagFor } from "better-supabase/next";

/** Every read of a guest's grants carries this tag. */
export const PORTAL_TAG = tagFor("portal");
