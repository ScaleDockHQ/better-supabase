import type { BlockOf } from "../define-block.ts";
import type { DonationsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDonations } from "./donations.ts";
import { donationsEvents } from "./events.ts";
import { givingBinding } from "./record-binding.ts";
import {
  donationFundInputSchema,
  giftInputSchema,
  pledgeInputSchema,
} from "./schemas.ts";

/** The `donations` block's manifest (ADR 0029). */
export const donationsBlock: BlockOf<
  "donations",
  typeof createDonations,
  DonationsEvents,
  Record<never, never>,
  never,
  typeof givingBinding
> = defineBlock({
  name: "donations",
  sql: ["donations"],
  events: donationsEvents,
  schemas: {
    donation: { input: giftInputSchema },
    pledge: { input: pledgeInputSchema },
    donation_fund: { input: donationFundInputSchema },
  },
  create: createDonations,
  record: givingBinding,
  category: "commerce",
  entities: {
    donation: { mutability: "state-machine" },
    pledge: { mutability: "editable", emits: { create: true, update: true } },
    donation_fund: { mutability: "editable", emits: { update: false } },
    donation_receipt: { mutability: "state-machine" },
  },
  concerns: ["lifecycle", "search"],
  description:
    "Gifts and pledges from donors (registered subjects) to funds and campaigns, each posted gift on the ledger in bigint minor units, charges through the versioned payments provider interface, and tax receipts numbered per organization with a yearly summary.",
  providers: [
    {
      option: "payments",
      type: "PaymentProvider",
      from: "better-supabase/commerce",
      required: false,
      description:
        "Takes payments; without one, payments are recorded by hand.",
      example: "stripePayments({ stripe })",
    },
  ],
});
