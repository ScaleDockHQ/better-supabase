import { tagFor } from "better-supabase/next";

/**
 * Every read of the maintenance pages (plans, meters, calibrations) carries
 * this tag, and every write of `maintenance-actions.ts` expires it through
 * `refreshCaller(auth, [MAINTENANCE_TAG])`.
 */
export const MAINTENANCE_TAG = tagFor("maintenance");
