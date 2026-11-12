import { tagFor } from "better-supabase/next";

/**
 * Every read of the finance lists and records carries this tag, and every write
 * of `finance-records-actions.ts` expires it. The reads show rows of invoices,
 * banking, payroll and the other finance blocks, so they carry those domains'
 * tags too.
 */
export const FINANCE_RECORDS_TAG = tagFor("finance-records");
