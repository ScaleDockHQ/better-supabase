export {
  createDeals,
  type Deal,
  type DealChange,
  type DealChangeResult,
  type DealContact,
  type DealField,
  type DealForecast,
  type DealHealth,
  type DealInput,
  type DealLineInput,
  type DealOutcome,
  type DealParty,
  type Deals,
  dealsSubjects,
  type DealsOptions,
  type DealTotals,
  type ForecastCategory,
} from "./deals.ts";
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
export { dealsBlock } from "./manifest.ts";
export { dealsEvents } from "./events.ts";
export type { DealsEvents } from "./events.ts";
