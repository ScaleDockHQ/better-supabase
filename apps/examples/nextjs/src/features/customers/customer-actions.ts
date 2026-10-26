"use server";

import { fromBetterResult } from "better-supabase";
import { withBetterResult } from "better-supabase/better-result";
import { after } from "next/server";
import * as v from "valibot";

import { recordAudit } from "@/features/audit/record-audit";
import { gettingStarted } from "@/features/onboarding/checklist";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { appErrors } from "@/lib/app-error";
import { logos } from "@/lib/buckets";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

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
    requireOrganization: true,
    authorize: async () => can(await getPermissions(), "customers.write"),
  },
  async ({ name }, { tenant: organizationId, db }) => {
    const { usage, onboarding } = db;
    const quota = await usage.consume(organizationId, "customers.created");

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
    await onboarding.complete(gettingStarted, "customer", organizationId);

    return created;
  },
);

/**
 * Uploads a new logo, points the row at its path, then removes the old one. The
 * row keeps the path; URLs are built when rendering.
 */
export const uploadCustomerLogo = bsb.action(
  {
    input: v.object({
      customerId: Id,
      logo: v.pipe(
        v.instance(File),
        v.check((file) => file.size > 0, "Pick a file"),
      ),
    }),
    requireOrganization: true,
    authorize: async () => can(await getPermissions(), "customers.write"),
  },
  async ({ customerId, logo }, { tenant: organizationId, db, supabase }) => {
    // A better-result value with an AppError, converted back for the action.
    const customer = await withBetterResult(db, appErrors).customers.get(
      customerId,
      { select: ["id", "logoPath"] },
    );

    if (customer.isErr()) {
      return fromBetterResult(customer);
    }

    return logos
      .connect(supabase)
      .replace(
        { organizationId, customerId, version: crypto.randomUUID() },
        logo,
        {
          contentType: logo.type,
          previous: customer.value.logoPath,
          commit: (path) => db.customers.update(customerId, { logoPath: path }),
        },
      );
  },
);
