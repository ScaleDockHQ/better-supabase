export {
  createEnrichment,
  type EnrichOptions,
  type Enrichment,
  type EnrichmentOptions,
  type EnrichmentReport,
  type EnrichmentResult,
  type EnrichmentSubject,
} from "./enrichment.ts";

export {
  domainOf,
  enrichmentProviderOf,
  peopleDataLabsEnrichment,
  type CompanyLookup,
  type CompanyProfile,
  type EnrichmentProvider,
  type PeopleDataLabsOptions,
  type PersonLookup,
  type PersonProfile,
} from "./providers.ts";

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

export { enrichmentBlock } from "./manifest.ts";

export { enrichmentEvents } from "./events.ts";

export type { EnrichmentEvents } from "./events.ts";
