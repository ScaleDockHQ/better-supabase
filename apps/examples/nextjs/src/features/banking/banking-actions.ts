"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/**
 * Matches a transaction to one invoice for its full amount; the database
 * records the invoice payment and refuses when the amounts don't add up.
 */
export const matchBankTransaction = bsb.action(
  {
    input: v.object({ transactionId: Id, invoiceId: Id }),
    requireTenant: true,
    permission: "banking.reconcile",
  },
  async ({ transactionId, invoiceId }, { db, auth }) => {
    const matched = await db.banking.match({
      transactionId,
      matches: [{ targetType: "invoice", targetId: invoiceId }],
    });

    if (!matched.ok) {
      return matched;
    }

    await refreshCaller(auth);

    return ok({ id: matched.data.id, status: matched.data.status });
  },
);

/** Marks a transaction as nothing to book, such as a transfer between accounts. */
export const ignoreBankTransaction = bsb.action(
  {
    input: v.object({ transactionId: Id }),
    requireTenant: true,
    permission: "banking.reconcile",
  },
  async ({ transactionId }, { db, auth }) => {
    const ignored = await db.banking.ignore({ transactionId });

    if (!ignored.ok) {
      return ignored;
    }

    await refreshCaller(auth);

    return ok({ id: ignored.data.id, status: ignored.data.status });
  },
);
