import "server-only";
import type { InvoiceStatus } from "better-supabase/blocks/invoices";
import type { Money } from "better-supabase/commerce";

import { money } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { cacheLife } from "next/cache";
import { unstable_rethrow } from "next/navigation";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

import { PLANS_TABLE } from "./billing-cache";

export interface PlanOption {
  readonly key: string;
  readonly name: string;
  /** The monthly price. */
  readonly price: Money;
  readonly features: readonly {
    readonly key: string;
    readonly value: unknown;
  }[];
}

/**
 * The plan catalog (`public.plans` and `public.plan_features`, which the
 * entitlements module reads). It is the same for every user, so it lives in the
 * shared cache: one user's first visit fills it for everyone, and writes to
 * `plans` expire it through the `plans` tag.
 */
export async function getPlans(): Promise<readonly PlanOption[]> {
  "use cache";
  // Not "max": the plans change in the seed and the Stripe dashboard, outside
  // the app's actions, so no updateTag fires for them.
  cacheLife("hours");
  bsb.tag(PLANS_TABLE);

  const plans = await bsb
    .admin()
    .plans.list({
      select: ["key", "name", "priceCents", "currency"],
      include: {
        planFeatures: { select: ["featureKey", "included", "value"] },
      },
      orderBy: { position: "asc" },
    })
    .orThrow();

  return plans.map((plan) => ({
    key: plan.key,
    name: plan.name,
    price: money(plan.priceCents, plan.currency),
    features: plan.planFeatures
      .filter((feature) => feature.included)
      .map((feature) => ({ key: feature.featureKey, value: feature.value })),
  }));
}

/** The organization's subscription; RLS limits it to members. */
export async function getSubscription(organizationId: string) {
  "use cache: private";
  const { db } = await bsb.cached();

  return db.subscriptions
    .get(
      { where: { organizationId } },
      { select: ["planKey", "status", "currentPeriodEnd"], optional: true },
    )
    .orThrow();
}

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
 * function, so `api.invoice_summaries` reads them with the caller's token and
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
    .$api("invoice_summaries", { tenant }, { returns: v.array(InvoiceRow) })
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
