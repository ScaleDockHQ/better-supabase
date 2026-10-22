export {
  createSegments,
  type Segment,
  type SegmentInput,
  type SegmentMember,
  type SegmentMembership,
  type SegmentRefresh,
  type SegmentRefreshReport,
  type Segments,
  type SegmentsOptions,
} from "./segments.ts";

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

export { segmentsBlock } from "./manifest.ts";

export { segmentsSqlOptions, type SegmentsSqlOptions } from "./options.ts";

export { segmentInputSchema } from "./schemas.ts";

export { segmentsEvents } from "./events.ts";
