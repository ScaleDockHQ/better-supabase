export {
  createDam,
  type Dam,
  type DamOptions,
  type DamRendition,
  type DamRenditionInput,
  type DamRenditionKind,
  type DamRenderInput,
  type DamUsageCheck,
  type DamUsageRight,
  type DamUsageRightInput,
  type DamUsageRightListOptions,
  type DamUsageRightStatus,
  type DamRenditionStatus,
} from "./dam.ts";

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

export { damBlock } from "./manifest.ts";

export { damUsageRightInputSchema } from "./schemas.ts";

export { damEvents } from "./events.ts";

export type {
  DamEvents,
  DamRenditionEventData,
  DamUsageRightEventData,
} from "./events.ts";

export {
  C2PA_AI_SOURCE_TYPES,
  c2paIsAiGenerated,
  c2paReaderOf,
  readC2paManifest,
  type C2paAction,
  type C2paIngredient,
  type C2paManifest,
  type C2paReader,
  type C2paReading,
} from "./c2pa.ts";

export {
  damUsageRightsToOdrl,
  ODRL_CONTEXT,
  type OdrlConstraint,
  type OdrlOptions,
  type OdrlPermission,
  type OdrlPolicy,
} from "./odrl.ts";
