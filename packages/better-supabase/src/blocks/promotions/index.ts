export {
  createPromotions,
  PROMOTION_KINDS,
  PROMOTION_SCOPES,
  type AppliedCode,
  type CodesInput,
  type PromotionCode,
  type PromotionDiscount,
  type PromotionInput,
  type PromotionKind,
  type PromotionScope,
  type Promotions,
  type SavedPromotion,
  type PromotionsOptions,
} from "./promotions.ts";

export {
  extendBlock,
  withBlockHooks,
  wrapTransport,
  type BlockHooks,
  type BlockTransportMiddleware,
} from "../../core/block-hooks.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
  type BlockTransport,
  type RpcClient,
} from "../../core/block-transport.ts";

export { promotionsBlock } from "./manifest.ts";

export { promotionsEvents } from "./events.ts";

export type { PromotionsEvents } from "./events.ts";
