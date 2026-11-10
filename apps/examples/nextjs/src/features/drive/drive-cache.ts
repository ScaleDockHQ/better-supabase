import { tagFor } from "better-supabase/next";

/**
 * Every read of the drive data carries this tag, and every write of its actions
 * expires it through `refreshCaller(auth, [DRIVE_TAG])`. A read in another
 * domain that shows the same rows carries it too.
 */
export const DRIVE_TAG = tagFor("drive");
