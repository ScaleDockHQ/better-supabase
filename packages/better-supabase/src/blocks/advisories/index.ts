export {
  createAdvisories,
  type Advisories,
  type AdvisoriesOptions,
  type Advisory,
  type AdvisoryDetail,
  type AdvisoryProduct,
  type EnrichmentReport,
  type OpenVexOptions,
  type ProductVersion,
  type StoredSbomComponent,
  type StoredVexStatement,
  type TrackedVulnerability,
  type VersionExposure,
} from "./advisories.ts";

export {
  CSAF_VERSION,
  createCsafHandler,
  csafFileName,
  renderCsaf,
  type CsafHandlerOptions,
  type CsafPublisher,
  type CsafSource,
  type RenderCsafOptions,
} from "./csaf.ts";

export {
  cvssSeverity,
  parseCvss,
  type CvssScore,
  type CvssSeverity,
} from "./cvss.ts";

export {
  MAX_SBOM_COMPONENTS,
  parseCycloneDx,
  type Sbom,
  type SbomComponent,
} from "./cyclonedx.ts";

export {
  osvRecordOf,
  publicVulnerabilityFeed,
  vulnerabilityFeedOf,
  type EpssScore,
  type FeedCallOptions,
  type KevEntry,
  type OsvRecord,
  type PublicVulnerabilityFeedOptions,
  type VulnerabilityFeed,
} from "./feed.ts";

export {
  OPENVEX_CONTEXT,
  renderOpenVex,
  type OpenVexInput,
  type OpenVexStatement,
} from "./openvex.ts";

export {
  ADVISORY_STATUSES,
  VEX_JUSTIFICATIONS,
  VEX_STATUSES,
  type AdvisoryRevision,
  type AdvisoryStatus,
  type PublishedAdvisory,
  type PublishedAdvisorySummary,
  type PublishedStatement,
  type PublishedVulnerability,
  type VexJustification,
  type VexStatus,
} from "./types.ts";

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

export { advisoriesBlock } from "./manifest.ts";

export { advisoriesEvents } from "./events.ts";

export type { AdvisoriesEvents } from "./events.ts";
