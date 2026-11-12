import { tagFor } from "better-supabase/next";

/** Every read of the public store carries this tag. */
export const STORE_TAG = tagFor("store");
