import type { BlockOf } from "../define-block.ts";
import type { DonationsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDonations } from "./donations.ts";
import { donationsEvents } from "./events.ts";
import { donationsSqlOptions } from "./options.ts";
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
  options: { donations: donationsSqlOptions },
  events: donationsEvents,
  schemas: {
    donation: { input: giftInputSchema },
    pledge: { input: pledgeInputSchema },
    donation_fund: { input: donationFundInputSchema },
  },
  create: createDonations,
  record: givingBinding,
  category: "commerce",
});
