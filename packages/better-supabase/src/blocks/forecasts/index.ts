export {
  createForecasts,
  type ForecastChangeKind,
  type ForecastChanges,
  type ForecastDealChange,
  type Forecasts,
  type ForecastSnapshot,
  type ForecastSnapshotDeal,
  type ForecastsOptions,
} from "./forecasts.ts";

export type { DealForecast } from "../deal-forecast.ts";

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

export { forecastsBlock } from "./manifest.ts";

export { forecastsEvents } from "./events.ts";

export type { ForecastsEvents } from "./events.ts";
