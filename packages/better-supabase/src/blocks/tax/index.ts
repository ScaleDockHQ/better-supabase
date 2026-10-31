export {
  createTax,
  type EuSalesListLine,
  type PrepareTaxReturnInput,
  type Tax,
  type TaxCode,
  type TaxCodeInput,
  type TaxCodeType,
  type TaxComputation,
  type TaxComputeInput,
  type TaxDate,
  type TaxGroup,
  type TaxLineInput,
  type TaxOptions,
  type TaxRate,
  type TaxReturn,
  type TaxReturnBox,
  type TaxReturnIssue,
} from "./tax.ts";

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

export { taxBlock } from "./manifest.ts";

export { prepareTaxReturnInputSchema, taxCodeInputSchema } from "./schemas.ts";

export { taxEvents } from "./events.ts";

export type {
  TaxCodeEventData,
  TaxEvents,
  TaxReturnPreparedEventData,
} from "./events.ts";
