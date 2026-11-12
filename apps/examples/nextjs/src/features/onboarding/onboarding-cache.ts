import { tagFor } from "better-supabase/next";

/** Every read of employee onboarding carries this tag; its actions expire it. */
export const ONBOARDING_TAG = tagFor("onboarding");
