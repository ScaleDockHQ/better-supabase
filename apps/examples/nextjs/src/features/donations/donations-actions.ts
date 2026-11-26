"use server";

import type { GiftInput } from "better-supabase/blocks/donations";

import { ok } from "better-supabase";
import { parseMoney } from "better-supabase/commerce";
import * as v from "valibot";

import type { Mutable } from "@/lib/block-status-list";

import { SHOP_CURRENCY } from "@/features/shop/shop-currency";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

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
    tags: () => [tags.donations()],
    refresh: true,
  },
  async ({ donorId, amount, fundId }, { db }) => {
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

    return ok(gift.data.id);
  },
);

/** Issues the numbered tax receipt for a posted gift. */
export const issueReceipt = bsb.action(
  {
    input: v.object({ giftId: Id }),
    requireTenant: true,
    permission: "donations.manage",
    tags: () => [tags.donations()],
    refresh: true,
  },
  async ({ giftId }, { db }) => {
    const receipt = await db.donations.issueGiftReceipt(giftId);

    if (!receipt.ok) {
      return receipt;
    }

    return ok(receipt.data.number);
  },
);
