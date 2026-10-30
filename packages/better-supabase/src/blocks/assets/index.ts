export {
  type Asset,
  type AssetAssignee,
  type AssetAssignment,
  type AssetDepreciation,
  type AssetDepreciationRun,
  type AssetDetail,
  type AssetInput,
  type AssetLinks,
  type AssetLinkTarget,
  type AssetListOptions,
  type AssetLocation,
  type AssetLocationDetail,
  type AssetLocationInput,
  type AssetLocationPatch,
  type AssetLocationStep,
  type AssetPatch,
  type Assets,
  type AssetsNear,
  type AssetsNearOptions,
  type AssetsOptions,
  type AssetStatus,
  createAssets,
  type DepreciationMethod,
  type GeoArea,
  type GeoPoint,
} from "./assets.ts";

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

export { assetsBlock } from "./manifest.ts";

export { assetsBinding } from "./record-binding.ts";

export { assetsEvents } from "./events.ts";

export type {
  AssetDepreciatedEventData,
  AssetDisposedEventData,
  AssetEventData,
  AssetLocationEventData,
  AssetsEvents,
} from "./events.ts";

export type { AssetsSqlOptions } from "./options.ts";
