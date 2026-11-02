import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What the `referral_code.*` events carry. */
export interface ReferralCodeEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly code: string;
  readonly referrerId: string;
  /** The invitation the code was made for, when there is one. */
  readonly invitationId: string | null;
}

/** What the `referral.*` events carry. */
export interface ReferralEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly codeId: string;
  readonly referrerId: string;
  readonly referredUserId: string | null;
  readonly referredOrganizationId: string | null;
  /** `attributed`, `qualified`, `rewarded` or `void`. */
  readonly status: string;
}

/** What `referral.rewarded` adds: the reward posted to the ledger. */
export interface ReferralRewardedEventData extends ReferralEventData {
  /** The reward in the unit's smallest amount, as text. */
  readonly amount: string;
  readonly unit: string;
}

/** The events of the `referrals` block: type to data. */
export type ReferralsEvents = {
  readonly "referral_code.created": ReferralCodeEventData;
  readonly "referral.attributed": ReferralEventData;
  readonly "referral.qualified": ReferralEventData;
  readonly "referral.rewarded": ReferralRewardedEventData;
  readonly "referral.voided": ReferralEventData;
};

/** The `referrals` block's event types, for its manifest and `onBlockEvent`. */
export const referralsEvents: Events<ReferralsEvents> = defineEvents({
  "referral_code.created": event<ReferralCodeEventData>(),
  "referral.attributed": event<ReferralEventData>(),
  "referral.qualified": event<ReferralEventData>(),
  "referral.rewarded": event<ReferralRewardedEventData>(),
  "referral.voided": event<ReferralEventData>(),
});
