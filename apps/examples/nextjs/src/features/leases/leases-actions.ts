"use server";

import type { LeaseInput } from "better-supabase/blocks/leases";

import { ok } from "better-supabase";
import { parseMoney } from "better-supabase/commerce";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import type { Mutable } from "@/lib/block-status-list";

import { SHOP_CURRENCY } from "@/features/shop/shop-currency";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

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
    tags: () => [tags.leases()],
    refresh: true,
  },
  async ({ unitId, customerId, startsOn, rent, deposit }, { db }) => {
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

    return ok(created.data.id);
  },
);

/** Starts a draft lease and holds its deposit on the ledger. */
export const activateLease = bsb.blockAction(
  ({ db }) => db.leases,
  "activate",
  {
    input: v.object({ leaseId: Id }),
    requireTenant: true,
    permission: "leases.manage",
    tags: () => [tags.leases()],
    refresh: true,
    args: ({ leaseId }) => [leaseId],
  },
  (activated) => activated.id,
);

/** Ends a lease today; the deposit goes back to the tenant. */
export const terminateLease = bsb.blockAction(
  ({ db }) => db.leases,
  "terminate",
  {
    input: v.object({
      leaseId: Id,
      reason: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(500))),
    }),
    requireTenant: true,
    permission: "leases.manage",
    tags: () => [tags.leases()],
    refresh: true,
    args: ({ leaseId, reason }) => [
      reason ? { leaseId, termination: { reason } } : { leaseId },
    ],
  },
  (ended) => ended.id,
);

/** Moves a payment from the balance due to rent received. */
export const recordRentPayment = bsb.blockAction(
  ({ db }) => db.leases,
  "recordPayment",
  {
    input: v.object({ leaseId: Id, amount: Amount }),
    requireTenant: true,
    permission: "leases.manage",
    tags: () => [tags.leases()],
    refresh: true,
    args: ({ leaseId, amount }) => [
      { leaseId, payment: { amount: parseMoney(amount, SHOP_CURRENCY) } },
    ],
  },
  (paid) => paid.leaseId,
);
