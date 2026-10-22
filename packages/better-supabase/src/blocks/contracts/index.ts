export {
  createContracts,
  type Contract,
  type ContractAction,
  type ContractChanges,
  type ContractInput,
  type ContractListOptions,
  type ContractObligation,
  type ContractRenewals,
  type Contracts,
  type ContractsOptions,
  type ContractSignatureInput,
  type ContractStatus,
  type ObligationInput,
  type ObligationListOptions,
  type ObligationStatus,
} from "./contracts.ts";

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

export { contractsBlock } from "./manifest.ts";

export { contractsSection } from "./section.ts";

export {
  contractChangesSchema,
  contractInputSchema,
  obligationInputSchema,
} from "./schemas.ts";

export { contractsEvents } from "./events.ts";

export type {
  ContractEventData,
  ContractRenewedEventData,
  ContractsEvents,
  ContractStatusChangedEventData,
  ObligationEventData,
} from "./events.ts";
