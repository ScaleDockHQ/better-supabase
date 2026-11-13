export {
  createImpersonation,
  type Impersonation,
  type ImpersonationOptions,
  type ImpersonationRequest,
  type ImpersonationSession,
  type ImpersonationTarget,
  type SupportSessionEndedBy,
} from "./impersonation.ts";

export { sqlTransport } from "../../core/block-transport.ts";

export type { BlockTransport } from "../../core/block-transport.ts";

export { impersonationBlock } from "./manifest.ts";

export { impersonationEvents } from "./events.ts";

export type { ImpersonationEvents } from "./events.ts";
