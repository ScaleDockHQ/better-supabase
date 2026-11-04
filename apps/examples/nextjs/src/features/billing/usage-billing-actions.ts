"use server";

import { generatedOptions } from "better-supabase/blocks";
import { rpcTransport } from "better-supabase/blocks/organizations";
import { createUsage } from "better-supabase/blocks/usage";
import * as v from "valibot";

import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsb } from "@/lib/supabase/server";

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
