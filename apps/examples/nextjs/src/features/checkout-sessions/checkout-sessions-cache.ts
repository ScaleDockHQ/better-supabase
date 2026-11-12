import { tagFor } from "better-supabase/next";

/** Every read of the checkout sessions carries this tag; the actions expire it. */
export const CHECKOUT_SESSIONS_TAG = tagFor("agent-checkout");
