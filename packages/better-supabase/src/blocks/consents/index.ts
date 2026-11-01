export {
  createConsents,
  type Consent,
  type ConsentEvidence,
  type ConsentGivenBy,
  type ConsentPurpose,
  type ConsentPurposeInput,
  type ConsentReceipt,
  type ConsentSignal,
  type ConsentSignalInput,
  type ConsentSignalKind,
  type Consents,
  type ConsentsOptions,
  type ConsentStatus,
  type LegalBasis,
  type RecordConsentInput,
} from "./consents.ts";

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

export { consentsBlock } from "./manifest.ts";

export { consentPurposeInputSchema } from "./schemas.ts";

export { consentsEvents } from "./events.ts";

export type {
  ConsentEventData,
  ConsentPurposeEventData,
  ConsentReceiptIssuedEventData,
  ConsentsEvents,
  ConsentSignalRecordedEventData,
} from "./events.ts";
