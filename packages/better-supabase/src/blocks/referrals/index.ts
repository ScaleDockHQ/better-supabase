export {
  createReferrals,
  type AttributeReferralInput,
  type CreateReferralCodeInput,
  type Referral,
  type ReferralCode,
  type ReferralListOptions,
  type Referrals,
  type ReferralsOptions,
  type ReferralReward,
  type ReferralStatus,
} from "./referrals.ts";

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

export { referralsBlock } from "./manifest.ts";

export { referralsEvents } from "./events.ts";

export type {
  ReferralCodeEventData,
  ReferralEventData,
  ReferralRewardedEventData,
  ReferralsEvents,
} from "./events.ts";
