import { tagFor } from "better-supabase/next";

/**
 * Every read of the sales pages (deals, pipelines, forecasts, segments, queues,
 * scoring, contracts, commissions, referrals and success) carries this tag, and
 * every write of `sales-actions.ts` expires it through `refreshCaller(auth,
 * [SALES_TAG, CRM_TAG])`.
 */
export const SALES_TAG = tagFor("sales");
