"use server";

import type { WarrantyClaimInput } from "better-supabase/blocks/warranty";

import { ok } from "better-supabase";
import { parseMoney } from "better-supabase/commerce";
import * as v from "valibot";

import type { Mutable } from "@/lib/block-status-list";

import { SHOP_CURRENCY } from "@/features/shop/shop-currency";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { WARRANTY_TAG } from "./warranty-cache";

const Id = v.pipe(v.string(), v.uuid());

/** Files a draft claim on an asset; the manufacturer is optional text. */
export const createClaim = bsb.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      assetId: Id,
      amount: v.pipe(v.string(), v.regex(/^\d+(\.\d{1,2})?$/)),
      manufacturer: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(200))),
    }),
    requireTenant: true,
    permission: "warranty.write",
  },
  async ({ title, assetId, amount, manufacturer }, { db, auth }) => {
    const parsed = parseMoney(amount, SHOP_CURRENCY);

    const input: Mutable<WarrantyClaimInput> = {
      title,
      assetId,
      amount: parsed.amount,
      currency: parsed.currency,
    };

    if (manufacturer) {
      input.manufacturer = manufacturer;
    }

    const created = await db.warranty.createClaim(input);

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth, [WARRANTY_TAG]);

    return ok(created.data.id);
  },
);

/** Moves a draft claim to submitted. */
export const submitClaim = bsb.action(
  {
    input: v.object({ claimId: Id }),
    requireTenant: true,
    permission: "warranty.write",
  },
  async ({ claimId }, { db, auth }) => {
    const submitted = await db.warranty.submit(claimId);

    if (!submitted.ok) {
      return submitted;
    }

    await refreshCaller(auth, [WARRANTY_TAG]);

    return ok(submitted.data.id);
  },
);

/** Approves or denies a submitted claim, or closes a decided one. */
export const decideClaim = bsb.action(
  {
    input: v.object({
      claimId: Id,
      status: v.picklist(["approved", "denied", "closed"]),
      decision: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(1000))),
    }),
    requireTenant: true,
    permission: "warranty.decide",
  },
  async ({ claimId, status, decision }, { db, auth }) => {
    const decided = await db.warranty.decide(claimId, status, decision);

    if (!decided.ok) {
      return decided;
    }

    await refreshCaller(auth, [WARRANTY_TAG]);

    return ok(decided.data.id);
  },
);
