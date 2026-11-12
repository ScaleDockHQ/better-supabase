"use server";

import type { LeaseInput } from "better-supabase/blocks/leases";

import { ok } from "better-supabase";
import { parseMoney } from "better-supabase/commerce";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import type { Mutable } from "@/lib/block-status-list";

import { SHOP_CURRENCY } from "@/features/shop/shop-currency";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { LEASES_TAG } from "./leases-cache";

const Id = v.pipe(v.string(), v.uuid());
const Amount = v.pipe(v.string(), v.regex(/^\d+(\.\d{1,2})?$/));

const PlainDate = v.pipe(
  v.string(),
  v.regex(/^\d{4}-\d{2}-\d{2}$/),
  v.transform((value) => Temporal.PlainDate.from(value)),
);

/** Drafts a monthly lease of an asset to a customer. */
export const createLease = bsb.action(
  {
    input: v.object({
      unitId: Id,
      customerId: Id,
      startsOn: PlainDate,
      rent: Amount,
      deposit: v.optional(Amount),
    }),
    requireTenant: true,
    permission: "leases.manage",
  },
  async ({ unitId, customerId, startsOn, rent, deposit }, { db, auth }) => {
    const input: Mutable<LeaseInput> = {
      unitId,
      party: { type: "customer", id: customerId },
      startsOn,
      rent: parseMoney(rent, SHOP_CURRENCY),
    };

    if (deposit) {
      input.deposit = parseMoney(deposit, SHOP_CURRENCY);
    }

    const created = await db.leases.create(input);

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth, [LEASES_TAG]);

    return ok(created.data.id);
  },
);

/** Starts a draft lease and holds its deposit on the ledger. */
export const activateLease = bsb.action(
  {
    input: v.object({ leaseId: Id }),
    requireTenant: true,
    permission: "leases.manage",
  },
  async ({ leaseId }, { db, auth }) => {
    const activated = await db.leases.activate(leaseId);

    if (!activated.ok) {
      return activated;
    }

    await refreshCaller(auth, [LEASES_TAG]);

    return ok(activated.data.id);
  },
);

/** Ends a lease today; the deposit goes back to the tenant. */
export const terminateLease = bsb.action(
  {
    input: v.object({
      leaseId: Id,
      reason: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(500))),
    }),
    requireTenant: true,
    permission: "leases.manage",
  },
  async ({ leaseId, reason }, { db, auth }) => {
    const ended = await db.leases.terminate(
      reason ? { leaseId, termination: { reason } } : { leaseId },
    );

    if (!ended.ok) {
      return ended;
    }

    await refreshCaller(auth, [LEASES_TAG]);

    return ok(ended.data.id);
  },
);

/** Moves a payment from the balance due to rent received. */
export const recordRentPayment = bsb.action(
  {
    input: v.object({ leaseId: Id, amount: Amount }),
    requireTenant: true,
    permission: "leases.manage",
  },
  async ({ leaseId, amount }, { db, auth }) => {
    const paid = await db.leases.recordPayment({
      leaseId,
      payment: { amount: parseMoney(amount, SHOP_CURRENCY) },
    });

    if (!paid.ok) {
      return paid;
    }

    await refreshCaller(auth, [LEASES_TAG]);

    return ok(paid.data.leaseId);
  },
);
