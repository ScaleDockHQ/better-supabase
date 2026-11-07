"use server";

import type { Result } from "better-supabase";

import { dbError, err, ok } from "better-supabase";
import { generatedOptions } from "better-supabase/blocks";
import { rpcTransport } from "better-supabase/blocks/organizations";
import { createUsage } from "better-supabase/blocks/usage";
import { parseMoney } from "better-supabase/commerce";
import { refresh } from "next/cache";
import * as v from "valibot";

import { gettingStarted } from "@/features/onboarding/checklist";
import { SHOP_CURRENCY } from "@/features/shop/shop-currency";
import { refreshCaller } from "@/lib/refresh-caller";
import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsb } from "@/lib/supabase/server";

import type { PlanOption } from "./billing-queries";

import { getPlans } from "./billing-queries";

/** Completes the "Review your plan" onboarding step. */
export const markPlanReviewed = bsb.action(
  { requireTenant: true, permission: "onboarding.complete" },
  async (_input, { tenant: organizationId, db }) => {
    const completed = await db.onboarding.complete({
      checklist: gettingStarted,
      step: "plan",
      organizationId,
    });

    if (!completed.ok) {
      return completed;
    }

    refresh();

    return ok(completed.data);
  },
);

/** The plan catalog and the organization's plan, for `usePlanPicker`. */
export const loadPlanCatalog = bsb.action(
  { requireTenant: true, permission: "billing.read" },
  async (_input, { tenant: organizationId, db }) => {
    const plans = await getPlans();

    return db.subscriptions
      .get(
        { where: { organizationId } },
        { select: ["planKey"], optional: true },
      )
      .map((subscription) => ({ plans, current: subscription?.planKey }));
  },
);

/**
 * Starts Stripe Checkout for a plan of the fixture's catalog (`public.plans`).
 * It runs on the server, so the Stripe key never reaches the browser: with the
 * billing SQL module and a test-mode key (`sk_test_...`), it returns
 * `billing.checkout(organizationId, { plan, successUrl, cancelUrl })`. This
 * example installs neither, so it answers `unsupported`.
 */
export const startCheckout = bsb.action(
  {
    input: v.object({ plan: v.string() }),
    requireTenant: true,
    permission: "billing.manage",
  },
  async ({ plan }): Promise<Result<{ url: string | undefined }>> => {
    const plans: readonly PlanOption[] = await getPlans();

    if (!plans.some((each) => each.key === plan)) {
      return err(dbError("not_found", `There is no "${plan}" plan`));
    }

    return err(
      dbError(
        "unsupported",
        "Checkout needs the billing SQL module and a Stripe test key, which this example doesn't install.",
      ),
    );
  },
);

/** A draft invoice with one line; it gets its number when it's issued. */
export const createDraftInvoice = bsb.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      amount: v.pipe(
        v.string(),
        v.trim(),
        v.regex(/^\d+(\.\d{1,2})?$/, "Enter an amount such as 190.00"),
      ),
    }),
    requireTenant: true,
    permission: "invoices.write",
  },
  async ({ title, amount }, { tenant, db, auth }) => {
    const created = await db.invoices.create({
      organizationId: tenant,
      input: { title, currency: SHOP_CURRENCY },
      lines: [
        {
          description: title,
          quantity: 1,
          unitAmount: parseMoney(amount, SHOP_CURRENCY),
        },
      ],
    });

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth);

    return ok(created.data.id);
  },
);

/** Issues a draft: it gets its number, today's date and its due date. */
export const issueInvoice = bsb.action(
  {
    input: v.object({ invoiceId: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "invoices.write",
  },
  async ({ invoiceId }, { db, auth }) => {
    const issued = await db.invoices.issue({ invoiceId });

    if (!issued.ok) {
      return issued;
    }

    await refreshCaller(auth);

    return ok(issued.data.status);
  },
);

/**
 * Rates the organization's usage of one month into a draft invoice. Billing
 * runs as the service role, so the action checks `invoices.write` first. A
 * month bills once: calling it again returns the first invoice.
 */
export const billUsageMonth = bsb.action(
  {
    input: v.object({ month: v.pipe(v.string(), v.regex(/^\d{4}-\d{2}$/)) }),
    requireTenant: true,
    permission: "invoices.write",
  },
  async ({ month }, { tenant }) => {
    const periodStart = Temporal.PlainDate.from(`${month}-01`);

    return createUsage({
      ...generatedOptions(blockConfig.usage),
      transport: rpcTransport(bsb.admin().$client, {
        schema: blockConfig.usage.api,
      }),
    }).billPeriod({
      organizationId: tenant,
      periodStart,
      periodEnd: periodStart.add({ months: 1 }),
    });
  },
);
