import type { BlockOf } from "../define-block.ts";
import type { ReferralsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { referralsEvents } from "./events.ts";
import { referralsSqlOptions } from "./options.ts";
import { createReferrals } from "./referrals.ts";

/** The `referrals` block's manifest. */
export const referralsBlock: BlockOf<
  "referrals",
  typeof createReferrals,
  ReferralsEvents
> = defineBlock({
  name: "referrals",
  sql: ["referrals"],
  events: referralsEvents,
  schemas: {},
  options: { referrals: referralsSqlOptions },
  create: createReferrals,
  recipes: [],
  category: "commerce",
  entities: {
    referral_code: {
      mutability: "append-only",
      emits: { create: true },
      permissions: { read: "referrals.read", create: "referrals.write" },
    },
    referral: {
      mutability: "state-machine",
      permissions: { read: "referrals.read", manage: "referrals.manage" },
    },
  },
  description:
    "Referral codes per member, attribution when the referred user or organization signs up, and a reward posted once to the ledger when the referral qualifies.",
});
