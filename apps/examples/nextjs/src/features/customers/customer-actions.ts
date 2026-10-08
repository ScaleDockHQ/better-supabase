"use server";

import { fromBetterResult, ok } from "better-supabase";
import { refresh } from "next/cache";
import { after } from "next/server";
import * as v from "valibot";

import { recordAudit } from "@/features/audit/record-audit";
import { can } from "@/features/user/user-permissions";
import { toAppResult } from "@/lib/app-error";
import { blocks } from "@/lib/blocks";
import { logos } from "@/lib/buckets";
import { bs } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/**
 * Mutations invalidate `bs:customers` with `updateTag` (see `createNext`).
 * The plan's `customers.created` quota is consumed first, so a full quota
 * fails with `quota_exceeded` before the row exists. With
 * `select better_supabase.set_rate_limit('/customers', 30)` (the
 * `rate-limit` SQL module), a burst of creates returns `rate_limited`.
 */
export const createCustomer = bs.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "customers.write"),
  },
  async ({ name }, { tenant: organizationId, db, supabase }) => {
    const { usage, onboarding } = blocks(supabase);
    const quota = await usage.consume(organizationId, "customers.created");
    if (!quota.ok) return quota;
    const created = await db.customers.create(
      { name, organizationId },
      { select: ["id", "name", "status"] },
    );
    if (!created.ok) return created;
    after(() =>
      recordAudit(supabase, {
        eventType: "customer.created",
        category: "customers",
        organizationId,
        targetType: "customer",
        record: created.data.id,
        targetLabel: name,
      }),
    );
    await onboarding.complete("customer", organizationId);
    return created;
  },
);

/**
 * Uploads a new logo, points the row at its path, then removes the old one.
 * The row keeps the path; URLs are built when rendering.
 */
export const uploadCustomerLogo = bs.action(
  {
    input: v.object({
      customerId: Id,
      logo: v.pipe(
        v.instance(File),
        v.check((file) => file.size > 0, "Pick a file"),
      ),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "customers.write"),
  },
  async ({ customerId, logo }, { tenant: organizationId, db, supabase }) => {
    // A better-result value with an AppError, converted back for the action.
    const customer = toAppResult(
      await db.customers.findById(customerId, { select: ["id", "logoPath"] }),
    );
    if (customer.isErr()) return fromBetterResult(customer);
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

/** A comment on a customer (the comments SQL module checks `comments.create`). */
export const addCustomerComment = bs.action(
  {
    input: v.object({
      customerId: Id,
      body: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(4000)),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "comments.create"),
  },
  async ({ customerId, body }, { tenant: organizationId, supabase }) => {
    const created = await blocks(supabase).comments.create({
      organizationId,
      subjectType: "customer",
      subjectId: customerId,
      body,
    });
    if (!created.ok) return created;
    refresh();
    return ok(created.data.id);
  },
);
