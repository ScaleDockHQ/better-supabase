import "server-only";
import type { InvoiceStatus } from "better-supabase/blocks/invoices";
import type { Money } from "better-supabase/commerce";

import { money } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

const INVOICE_STATUSES = [
  "draft",
  "issued",
  "partially_paid",
  "paid",
  "void",
  "uncollectible",
] as const satisfies readonly InvoiceStatus[];

const MinorUnits = v.pipe(v.string(), v.regex(/^-?\d+$/));

const InvoiceRow = v.object({
  id: v.pipe(v.string(), v.uuid()),
  identifier: v.nullable(v.string()),
  title: v.string(),
  status: v.picklist(INVOICE_STATUSES),
  currency: v.string(),
  total: MinorUnits,
  balance: MinorUnits,
  issuedOn: v.nullable(v.string()),
  dueOn: v.nullable(v.string()),
  overdue: v.boolean(),
});

export interface InvoiceSummary {
  readonly id: string;
  readonly identifier: string | null;
  readonly title: string;
  readonly status: InvoiceStatus;
  readonly total: Money;
  readonly balance: Money;
  readonly issuedOn: string | null;
  readonly dueOn: string | null;
  readonly overdue: boolean;
}

/**
 * The organization's invoices, newest first. The invoices block has no list
 * function, so `api.billing_invoices` reads them with the caller's token and
 * the block's `invoices.read` policy.
 */
async function loadInvoices(): Promise<readonly InvoiceSummary[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const rows = await db
    .$api("billing_invoices", { tenant }, { returns: v.array(InvoiceRow) })
    .orThrow();

  return rows.map(({ currency, total, balance, ...row }) => ({
    ...row,
    total: money(BigInt(total), currency),
    balance: money(BigInt(balance), currency),
  }));
}

export type Invoices =
  | { readonly kind: "ok"; readonly invoices: readonly InvoiceSummary[] }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
export async function getInvoices(): Promise<Invoices> {
  try {
    const invoices = await loadInvoices();

    return invoices ? { kind: "ok", invoices } : { kind: "no-organization" };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
