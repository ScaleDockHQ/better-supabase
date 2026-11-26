"use server";

import * as v from "valibot";

import { BILLING_TAG } from "@/features/billing/billing-cache";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/**
 * Matches a transaction to one invoice for its full amount; the database
 * records the invoice payment and refuses when the amounts don't add up.
 */
export const matchBankTransaction = bsb.blockAction(
  ({ db }) => db.banking,
  "match",
  {
    input: v.object({ transactionId: Id, invoiceId: Id }),
    requireTenant: true,
    permission: "banking.reconcile",
    tags: () => [tags.banking(), BILLING_TAG],
    refresh: true,
    args: ({ transactionId, invoiceId }) => [
      {
        transactionId,
        matches: [{ targetType: "invoice", targetId: invoiceId }],
      },
    ],
  },
  (matched) => ({ id: matched.id, status: matched.status }),
);

/** Marks a transaction as nothing to book, such as a transfer between accounts. */
export const ignoreBankTransaction = bsb.blockAction(
  ({ db }) => db.banking,
  "ignore",
  {
    input: v.object({ transactionId: Id }),
    requireTenant: true,
    permission: "banking.reconcile",
    tags: () => [tags.banking(), BILLING_TAG],
    refresh: true,
  },
  (ignored) => ({ id: ignored.id, status: ignored.status }),
);
