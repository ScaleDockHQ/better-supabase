"use server";

import { dbError, err, fromBetterResult } from "better-supabase";
import { toSession } from "better-supabase/next";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { toAppResult } from "@/lib/app-error";
import { logos } from "@/lib/buckets";
import { bs } from "@/lib/supabase/server";

/**
 * Mutations invalidate `bs:customers` with `updateTag` (see `createNext`).
 * With `select better_supabase.set_rate_limit('/customers', 30)` (the
 * `rate-limit` kit module), a burst of creates returns `rate_limited`.
 */
export const createCustomer = bs.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.minLength(1), v.maxLength(200)),
    }),
  },
  async ({ name }, { auth, db }) => {
    if (!can(toSession(auth), "customers.write")) {
      return err(dbError("forbidden", "You cannot add customers"));
    }
    const organizationId =
      auth.kind === "user" ? auth.claims.app_metadata?.tenant_id : undefined;
    if (!organizationId) {
      return err(dbError("forbidden", "Your account has no organization"));
    }
    return db.customers.create(
      { name, organizationId },
      { select: ["id", "name", "status"] },
    );
  },
);

/**
 * Uploads a new logo, points the row at its path, then removes the old one.
 * The row keeps the path; URLs are signed when rendering.
 */
export const uploadCustomerLogo = bs.action(
  {
    input: v.object({
      customerId: v.pipe(v.string(), v.uuid()),
      logo: v.pipe(
        v.instance(File),
        v.check((file) => file.size > 0, "Pick a file"),
      ),
    }),
  },
  async ({ customerId, logo }, { auth, db, supabase }) => {
    if (!can(toSession(auth), "customers.write")) {
      return err(dbError("forbidden", "You cannot change customers"));
    }
    const orgId =
      auth.kind === "user" ? auth.claims.app_metadata?.tenant_id : undefined;
    if (!orgId) {
      return err(dbError("forbidden", "Your account has no organization"));
    }
    // A better-result value with an AppError, converted back for the action.
    const customer = toAppResult(
      await db.customers.findById(customerId, { select: ["id", "logoPath"] }),
    );
    if (customer.isErr()) return fromBetterResult(customer);
    return logos
      .connect(supabase)
      .replace({ orgId, customerId, version: crypto.randomUUID() }, logo, {
        contentType: logo.type,
        previous: customer.value.logoPath,
        commit: (path) => db.customers.update(customerId, { logoPath: path }),
      });
  },
);
