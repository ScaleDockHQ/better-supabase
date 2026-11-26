import { tagFor } from "better-supabase/next";

/**
 * Every read of appraisals carries this tag; a review, calibration or sign-off
 * expires it.
 */
export const APPRAISALS_TAG = tagFor("appraisals");
