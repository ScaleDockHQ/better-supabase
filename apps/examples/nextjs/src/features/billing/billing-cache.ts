import { tagFor } from "better-supabase/next";

/** The table whose tag expires the shared plan catalog. */
export const PLANS_TABLE = "plans";

/**
 * Every read of invoices and the subscription carries this tag, and every write
 * of the billing actions expires it through `refreshCaller(auth,
 * [BILLING_TAG])`. The banking, shop and payables reads that show the same
 * invoices carry it too.
 */
export const BILLING_TAG = tagFor("billing");
