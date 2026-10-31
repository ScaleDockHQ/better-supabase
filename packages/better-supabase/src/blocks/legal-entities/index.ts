export {
  createLegalEntities,
  type CreateLegalEntityInput,
  type LegalEntities,
  type LegalEntitiesOptions,
  type LegalEntity,
  type LegalEntityFiscal,
  type LegalEntityInput,
  type ResolvedSetting,
} from "./legal-entities.ts";

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

export { legalEntitiesBlock } from "./manifest.ts";

export {
  legalEntitiesSqlOptions,
  type LegalEntitiesSqlOptions,
} from "./options.ts";

export { legalEntityInputSchema } from "./schemas.ts";

export { legalEntitiesEvents } from "./events.ts";

export type { LegalEntitiesEvents, LegalEntityEventData } from "./events.ts";
