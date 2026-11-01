export {
  ADJUST_REASONS,
  createInventory,
  LOCATION_KINDS,
  PURCHASE_ORDER_STATUSES,
  type AdjustReason,
  type Inventory,
  type InventoryOptions,
  type LocationAddress,
  type LocationInput,
  type LocationKind,
  type PurchaseOrderInput,
  type PurchaseOrderLine,
  type PurchaseOrderStatus,
  type Receipt,
  type ReceiptLine,
  type Reservation,
  type ReserveInput,
  type SavedLocation,
  type StockChange,
  type StockCount,
  type StockLine,
  type TransferInput,
  type TransferLine,
} from "./inventory.ts";

export {
  COUNT_STATUSES,
  inventoryCounts,
  type CountLine,
  type CountLineInput,
  type CountStatus,
  type InventoryCounts,
  type OpenCountInput,
  type OpenedCount,
  type PostedCount,
} from "./counts.ts";

export {
  ALLOCATION_STATUSES,
  COSTING_METHODS,
  TRACKING_MODES,
  type Allocation,
  type AllocationInput,
  type AllocationStatus,
  type Bin,
  type BinInput,
  type CostingMethod,
  type ExpiringLot,
  type InventoryTracking,
  type Lot,
  type StockBucket,
  type StockDetail,
  type StockItem,
  type StockItemInput,
  type StockLevelDetail,
  type StockValuation,
  type TrackingMode,
} from "./tracking.ts";

export {
  REQUISITION_STATUSES,
  type InventoryProcurement,
  type PurchaseRequisition,
  type RequisitionInput,
  type RequisitionLine,
  type RequisitionLineInput,
  type RequisitionStatus,
} from "./procurement.ts";

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

export type {
  InventoryExpiringLot,
  InventoryLowStock,
  InventoryOverview,
  InventoryReads,
} from "./reads.ts";

export { inventoryBlock } from "./manifest.ts";

export { inventoryEvents } from "./events.ts";

export type { InventoryEvents } from "./events.ts";
