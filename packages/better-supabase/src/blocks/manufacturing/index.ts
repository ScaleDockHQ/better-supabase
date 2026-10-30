export {
  createManufacturing,
  type Bom,
  type BomComponent,
  type BomComponentInput,
  type BomDetail,
  type BomExplosion,
  type BomExplosionLine,
  type BomInput,
  type BomOperation,
  type BomOperationInput,
  type BomStatus,
  type BomUse,
  type LotGenealogy,
  type LotGenealogyLine,
  type LotRecall,
  type Manufacturing,
  type ManufacturingOptions,
  type MaterialRequirement,
  type MaterialRequirements,
  type ProductionConsumption,
  type ProductionOperationStatus,
  type ProductionOrder,
  type ProductionOrderComponent,
  type ProductionOrderDetail,
  type ProductionOrderInput,
  type ProductionOrderListOptions,
  type ProductionOrderOperation,
  type ProductionOrderStatus,
  type ProductionOutputLot,
  type RequirementAction,
  type RequirementDocuments,
  type RequirementItem,
  type TraceLot,
  type WorkCenter,
  type WorkCenterInput,
} from "./manufacturing.ts";

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

export { manufacturingBlock } from "./manifest.ts";

export {
  manufacturingSqlOptions,
  type ManufacturingSqlOptions,
} from "./options.ts";

export {
  bomInputSchema,
  productionOrderInputSchema,
  workCenterInputSchema,
} from "./schemas.ts";

export { manufacturingEvents } from "./events.ts";

export type {
  BomActivatedEventData,
  ManufacturingEvents,
  ProductionOrderCanceledEventData,
  ProductionOrderCompletedEventData,
  ProductionOrderEventData,
} from "./events.ts";
