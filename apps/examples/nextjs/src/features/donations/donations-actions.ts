"use server";

import type { GiftInput } from "better-supabase/blocks/donations";

import { ok } from "better-supabase";
import { parseMoney } from "better-supabase/commerce";
import * as v from "valibot";

import type { Mutable } from "@/lib/block-status-list";

import { SHOP_CURRENCY } from "@/features/shop/shop-currency";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { DONATIONS_TAG } from "./donations-cache";

const Id = v.pipe(v.string(), v.uuid());

/** Records a gift received outside the payment provider and posts it. */
export const recordGift = bsb.action(
  {
    input: v.object({
      donorId: Id,
      amount: v.pipe(v.string(), v.regex(/^\d+(\.\d{1,2})?$/)),
      fundId: v.optional(v.union([Id, v.literal("")])),
    }),
    requireTenant: true,
    permission: "donations.manage",
  },
  async ({ donorId, amount, fundId }, { db, auth }) => {
    const input: Mutable<GiftInput> = {
      donor: { type: "customer", id: donorId },
      amount: parseMoney(amount, SHOP_CURRENCY),
    };

    if (fundId) {
      input.fundId = fundId;
    }

    const gift = await db.donations.recordGift(input);

    if (!gift.ok) {
      return gift;
    }

    await refreshCaller(auth, [DONATIONS_TAG]);

    return ok(gift.data.id);
  },
);

/** Issues the numbered tax receipt for a posted gift. */
export const issueReceipt = bsb.action(
  {
    input: v.object({ giftId: Id }),
    requireTenant: true,
    permission: "donations.manage",
  },
  async ({ giftId }, { db, auth }) => {
    const receipt = await db.donations.issueGiftReceipt(giftId);

    if (!receipt.ok) {
      return receipt;
    }

    await refreshCaller(auth, [DONATIONS_TAG]);

    return ok(receipt.data.number);
  },
);
