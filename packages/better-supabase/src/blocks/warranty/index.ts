export {
  createWarranty,
  type Warranty,
  type WarrantyClaim,
  type WarrantyClaimInput,
  type WarrantyClaimListOptions,
  type WarrantyOptions,
} from "./warranty.ts";

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

export { warrantyBlock } from "./manifest.ts";

export { warrantyEvents } from "./events.ts";

export type {
  WarrantyClaimDecidedEventData,
  WarrantyClaimEventData,
  WarrantyEvents,
} from "./events.ts";

export type {
  WarrantyDecision,
  WarrantyStatus,
} from "../../sql/modules/warranty-values.ts";
