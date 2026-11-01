import type { BlockCall } from "../../core/block-helpers.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BillingOverview } from "../../sql/modules/billing-reads.ts";

import { decodeRead } from "../../core/read-type.ts";
import { BILLING_OVERVIEW_RESULT } from "../../sql/modules/billing-reads.ts";

export type { BillingOverview } from "../../sql/modules/billing-reads.ts";

/** The composed reads of the billing client. */
export interface BillingReads {
  /**
   * The billing page in one call: the Stripe customer, the seat count, the
   * subscription item, the latest `invoiceLimit` invoices (default 10) and,
   * with the `usage` block, the status of each meter. `status` and `invoices`
   * give the same pieces one call at a time.
   */
  overview(input: {
    organizationId: string;
    invoiceLimit?: number | undefined;
  }): AsyncResult<BillingOverview>;
}

export function billingReads(call: BlockCall): BillingReads {
  return {
    overview: ({ organizationId, invoiceLimit }) =>
      call(
        "billing_overview",
        {
          tenant: organizationId,
          ...(invoiceLimit === undefined
            ? {}
            : { invoice_limit: invoiceLimit }),
        },
        (value) =>
          decodeRead<BillingOverview>(
            BILLING_OVERVIEW_RESULT,
            value,
            "billing_overview",
          ),
      ),
  };
}
