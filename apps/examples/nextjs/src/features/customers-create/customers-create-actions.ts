"use server";

import { after } from "next/server";
import * as v from "valibot";

import { recordAudit } from "@/features/audit/record-audit";
import { gettingStarted } from "@/features/onboarding/checklist";
import { bsbShell as bsb } from "@/lib/supabase/server-shell";

/**
 * Mutations invalidate `bsb:customers` with `updateTag` (see `createNext`). The
 * plan's `customers.created` quota is consumed first, so a full quota fails
 * with `quota_exceeded` before the row exists. With `select
 * better_supabase.set_rate_limit('/customers', 30)` (the `rate-limit` SQL
 * module), a burst of creates returns `rate_limited`.
 */
export const createCustomer = bsb.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
    }),
    requireTenant: true,
    permission: "customers.write",
  },
  async ({ name }, { tenant: organizationId, db }) => {
    const { usage, onboarding } = db;

    const quota = await usage.consume({
      organizationId,
      meter: "customers.created",
    });

    if (!quota.ok) {
      return quota;
    }

    const created = await db.customers.create(
      { name, organizationId },
      { select: ["id", "name", "status"] },
    );

    if (!created.ok) {
      return created;
    }

    after(() =>
      recordAudit(db, {
        eventType: "customer.created",
        category: "customers",
        organizationId,
        targetType: "customer",
        record: created.data.id,
        targetLabel: name,
      }),
    );
    await onboarding.complete({
      checklist: gettingStarted,
      step: "customer",
      organizationId,
    });

    return created;
  },
);
