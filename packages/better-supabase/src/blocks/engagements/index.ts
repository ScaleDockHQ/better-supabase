export {
  createEngagements,
  type Engagement,
  type EngagementInput,
  type Engagements,
  type EngagementsOptions,
  type EngagementSubject,
} from "./engagements.ts";

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

export { engagementsBlock } from "./manifest.ts";

export { engagementsEvents } from "./events.ts";

export type { EngagementsEvents } from "./events.ts";

export { engagementChangeSchema, engagementInputSchema } from "./schemas.ts";
