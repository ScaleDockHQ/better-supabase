export {
  createDonations,
  type DonationFund,
  type DonationFundInput,
  type DonationPaymentOutcome,
  type DonationReceipt,
  type Donations,
  type DonationsOptions,
  type DueInstallmentOptions,
  type Gift,
  type GiftInput,
  type GiftListOptions,
  type GiftStatus,
  type GiveInput,
  type GiveOutcome,
  type GivingSummary,
  type Pledge,
  type PledgeChargeOutcome,
  type PledgeFrequency,
  type PledgeInput,
  type PledgeInstallment,
  type PledgeListOptions,
  type PledgeStatus,
  type PledgeUpdate,
  type ReceiptListOptions,
} from "./donations.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
} from "../../core/block-hooks.ts";

export type {
  BlockHooks,
  BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport, RpcClient } from "../../core/block-transport.ts";

export { donationsBlock } from "./manifest.ts";

export { givingBinding } from "./record-binding.ts";

export {
  donationFundInputSchema,
  giftInputSchema,
  pledgeInputSchema,
} from "./schemas.ts";

export { donationsEvents } from "./events.ts";

export type {
  DonationEventData,
  DonationReceiptEventData,
  DonationsEvents,
  PledgeEventData,
} from "./events.ts";
