import { tagFor } from "better-supabase/next";

/** Every read of the reminder levels and runs carries this tag. */
export const DUNNING_TAG = tagFor("dunning");
