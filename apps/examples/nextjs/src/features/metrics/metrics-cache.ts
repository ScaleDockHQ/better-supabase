import { tagFor } from "better-supabase/next";

/** The metric reads carry this tag, so a write to customers can expire them. */
export const METRICS_TAG = tagFor("metrics");
