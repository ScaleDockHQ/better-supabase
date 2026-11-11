import { tagFor } from "better-supabase/next";

/** Every read of the leases carries this tag; the lease actions expire it. */
export const LEASES_TAG = tagFor("leases");
