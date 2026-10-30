import type { Money } from "../../commerce/money.ts";
import type { StockDetail } from "../../commerce/stock-detail.ts";
import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockOptions } from "../shared.ts";

import { detailArg } from "../../commerce/stock-detail.ts";
import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  BOM_STATUSES,
  PRODUCTION_OPERATION_STATUSES,
  PRODUCTION_ORDER_STATUSES,
  REQUIREMENT_ACTIONS,
} from "../../sql/modules/manufacturing-values.ts";
import { optionalMoneyOf } from "../money-codec.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Where a bill of materials version stands; one per variant is active. */
export type BomStatus = (typeof BOM_STATUSES)[number];

/** Where a production order stands. */
export type ProductionOrderStatus = (typeof PRODUCTION_ORDER_STATUSES)[number];

/** Where one operation of a production order stands. */
export type ProductionOperationStatus =
  (typeof PRODUCTION_OPERATION_STATUSES)[number];

/** What material requirements suggest for a shortage. */
export type RequirementAction = (typeof REQUIREMENT_ACTIONS)[number];

/**
 * Quantities are numbers in the variant's unit, with up to its `scale`
 * decimals, as in the inventory block.
 */
export interface Bom {
  readonly id: string;
  readonly organizationId: string;
  /** The variant the bill of materials makes. */
  readonly variantId: string;
  /** 1, 2, 3 per variant. */
  readonly version: number;
  readonly status: BomStatus;
  /** How many units of the variant the components make. */
  readonly quantity: number;
  readonly note?: string;
  readonly activatedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface BomComponent {
  readonly id: string;
  readonly variantId: string;
  /** Per `Bom.quantity` units of the output. */
  readonly quantity: number;
  /** Planned scrap in basis points, added to what an order needs. */
  readonly scrapBps: number;
  /** The operation that consumes it. */
  readonly operationId?: string;
  readonly position: number;
}

export interface BomOperation {
  readonly id: string;
  /** The routing order, such as 10, 20, 30. */
  readonly sequence: number;
  readonly workCenterId: string;
  readonly title: string;
  readonly setupMinutes: number;
  readonly runMinutesPerUnit: number;
  /** A drive node with the work instructions. */
  readonly instructionsNodeId?: string;
  /** An inspection kind scheduled when the operation starts. */
  readonly inspectionTemplate?: string;
}

/** A bill of materials version with its components and routing. */
export interface BomDetail extends Bom {
  readonly components: readonly BomComponent[];
  readonly operations: readonly BomOperation[];
}

export interface BomComponentInput {
  readonly variantId: string;
  readonly quantity: number;
  /** 0 to 10000. Default 0. */
  readonly scrapBps?: number;
  /** The `sequence` of the operation that consumes it. */
  readonly operation?: number;
}

export interface BomOperationInput {
  readonly sequence: number;
  readonly workCenterId: string;
  readonly title: string;
  readonly setupMinutes?: number;
  readonly runMinutesPerUnit?: number;
  readonly instructionsNodeId?: string;
  readonly inspectionTemplate?: string;
}

export interface BomInput {
  /** Default 1. */
  readonly quantity?: number;
  readonly components: readonly BomComponentInput[];
  readonly operations?: readonly BomOperationInput[];
  readonly note?: string;
}

/** One line of an explosion, every level down. */
export interface BomExplosionLine {
  /** 1 for the components of the exploded variant. */
  readonly level: number;
  readonly variantId: string;
  readonly parentVariantId: string;
  readonly bomId: string;
  readonly quantity: number;
  /** It has an active bill of materials of its own. */
  readonly made: boolean;
}

export interface BomExplosion {
  readonly variantId: string;
  readonly quantity: number;
  readonly lines: readonly BomExplosionLine[];
  /** The purchased materials, summed over every level. */
  readonly materials: readonly {
    readonly variantId: string;
    readonly quantity: number;
  }[];
}

/** A bill of materials a variant goes into. */
export interface BomUse {
  /** 1 where the variant is a direct component. */
  readonly level: number;
  readonly bomId: string;
  readonly variantId: string;
  readonly version: number;
  readonly status: BomStatus;
  readonly quantity: number;
}

export interface WorkCenter {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  /** The assets block record of the machine or line. */
  readonly assetId?: string;
  readonly hoursPerDay: number;
  /** Per hour; absent without a currency. */
  readonly costRate?: Money;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface WorkCenterInput {
  readonly name?: string;
  readonly assetId?: string | null;
  readonly hoursPerDay?: number;
  /** Per hour. */
  readonly costRate?: Money;
  readonly archived?: boolean;
}

/**
 * A production order. `F` types the extra columns the `fields` schema
 * describes.
 */
export interface ProductionOrder<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  /** Such as `MO-2026-0001`. */
  readonly number: string;
  readonly variantId: string;
  /** The active bill of materials version pinned at creation. */
  readonly bomId: string;
  readonly quantity: number;
  /** Where components leave and the output arrives. */
  readonly locationId: string;
  readonly dueOn?: Temporal.PlainDate;
  readonly status: ProductionOrderStatus;
  readonly producedQuantity: number;
  readonly scrapQuantity: number;
  readonly outputLotId?: string;
  /** Set on completion, when the order has a currency. */
  readonly materialCost?: Money;
  readonly laborCost?: Money;
  readonly note?: string;
  readonly releasedAt?: Temporal.Instant;
  readonly startedAt?: Temporal.Instant;
  readonly completedAt?: Temporal.Instant;
  readonly canceledAt?: Temporal.Instant;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly fields: ExtraFields<F>;
}

export interface ProductionOrderOperation {
  readonly id: string;
  readonly operationId?: string;
  readonly sequence: number;
  readonly workCenterId: string;
  readonly title: string;
  readonly plannedMinutes: number;
  readonly status: ProductionOperationStatus;
  readonly startedAt?: Temporal.Instant;
  readonly finishedAt?: Temporal.Instant;
  readonly operatorId?: string;
  readonly minutes?: number;
  /** The inspection the operation's template scheduled. */
  readonly inspectionId?: string;
}

/** A component of a production order: what it needs and what it took. */
export interface ProductionOrderComponent {
  readonly componentId: string;
  readonly variantId: string;
  /** For the order's quantity, planned scrap included. */
  readonly quantity: number;
  readonly allocated: number;
  readonly backordered: number;
  readonly consumed: number;
}

export interface ProductionConsumption {
  readonly id: string;
  readonly variantId: string;
  readonly lotId?: string;
  readonly serial?: string;
  readonly quantity: number;
  /** The stock value it took; absent for an item without costing. */
  readonly cost?: Money;
  readonly movementId: string;
  readonly createdAt: Temporal.Instant;
}

export interface ProductionOrderDetail<
  F extends object = Record<never, never>,
> extends ProductionOrder<F> {
  readonly operations: readonly ProductionOrderOperation[];
  readonly components: readonly ProductionOrderComponent[];
  readonly consumptions: readonly ProductionConsumption[];
}

export interface ProductionOrderInput<F extends object = Record<never, never>> {
  readonly variantId: string;
  readonly quantity: number;
  /** Default: the organization's first active location by code. */
  readonly locationId?: string;
  readonly dueOn?: Temporal.PlainDate;
  /** An active version; default the variant's active one. */
  readonly bomId?: string;
  readonly note?: string;
  /** The extra columns, keyed by database name. */
  readonly fields?: Partial<F>;
}

export interface ProductionOrderListOptions {
  readonly status?: ProductionOrderStatus;
  readonly variantId?: string;
  /** 1 to 500. Default 100. */
  readonly limit?: number;
}

/** The lot `complete` puts the output into. */
export type ProductionOutputLot =
  | { readonly lotId: string; readonly serials?: readonly string[] }
  | {
      readonly code: string;
      /** `YYYY-MM-DD`. */
      readonly expiresOn?: string;
      readonly serials?: readonly string[];
    }
  | { readonly serials: readonly string[] };

export interface TraceLot {
  readonly lotId: string;
  readonly code: string;
  readonly variantId: string;
  /** `YYYY-MM-DD`. */
  readonly expiresOn?: string;
}

export interface LotGenealogyLine extends TraceLot {
  readonly level: number;
  /** The lot one level closer to the one traced. */
  readonly fromLotId: string;
  readonly orderId: string;
  readonly quantity: number;
}

export interface LotGenealogy {
  readonly lotId: string;
  /** `down` lists what the lot was made from, `up` what was made from it. */
  readonly direction: "up" | "down";
  readonly lots: readonly LotGenealogyLine[];
}

export interface LotRecall {
  readonly lotId: string;
  /** The lot and every lot made from it. */
  readonly lots: readonly TraceLot[];
  /** Their stock still on hand. */
  readonly stock: readonly {
    readonly lotId: string;
    readonly variantId: string;
    readonly locationId: string;
    readonly binId?: string;
    readonly onHand: number;
  }[];
  /** The documents they left stock for, such as an order or a shipment. */
  readonly documents: readonly {
    readonly referenceType: string;
    readonly referenceId: string;
    readonly lotId: string;
    readonly variantId: string;
    readonly quantity: number;
    readonly at: Temporal.Instant;
  }[];
  /** The production orders that consumed them. */
  readonly orders: readonly {
    readonly orderId: string;
    readonly number: string;
    readonly status: ProductionOrderStatus;
    readonly variantId: string;
    readonly outputLotId?: string;
  }[];
}

export interface MaterialRequirement {
  readonly variantId: string;
  /** `produce` with an active bill of materials, else `purchase`. */
  readonly action: RequirementAction;
  readonly bomId?: string;
  /** What to produce or buy to reach the reorder point. */
  readonly quantity: number;
  readonly available: number;
  readonly incoming: number;
  /** Open production orders of the variant. */
  readonly planned: number;
  readonly demand: number;
  readonly reorderPoint?: number;
}

export interface MaterialRequirements {
  readonly organizationId: string;
  readonly horizonDays: number;
  readonly items: readonly MaterialRequirement[];
}

export interface RequirementItem {
  readonly variantId: string;
  readonly action: RequirementAction;
  readonly quantity: number;
  readonly dueOn?: Temporal.PlainDate;
  readonly locationId?: string;
  /** For a purchase: a `config.subjects` record for the supplier. */
  readonly supplier?: { readonly type: string; readonly id: string };
  /** For a purchase; default the item's average cost. */
  readonly unitCost?: Money;
}

export interface RequirementDocuments<F extends object = Record<never, never>> {
  readonly productionOrders: readonly ProductionOrderDetail<F>[];
  /** The inventory block's draft purchase orders. */
  readonly purchaseOrders: readonly { readonly id: string }[];
  /**
   * The inventory block's purchase requisitions, with
   * `options.purchaseSuggestions: "requisition"`.
   */
  readonly purchaseRequisitions: readonly { readonly id: string }[];
}

export interface Manufacturing<F extends object = Record<never, never>> {
  /**
   * Saves a new version of the variant's bill of materials, or changes a draft
   * one (`bomId`). Needs `manufacturing.write`.
   */
  saveBom(
    variantId: string,
    input: BomInput,
    bomId?: string,
  ): AsyncResult<BomDetail>;
  /**
   * Makes a version the active one and archives the previous; fails with
   * `BOM_CYCLE` when the variant would end up in its own components. Needs
   * `manufacturing.manage`.
   */
  activateBom(bomId: string): AsyncResult<BomDetail>;
  getBom(bomId: string): AsyncResult<BomDetail>;
  /** Every version, by variant and the latest first. */
  listBoms(variantId?: string): AsyncResult<readonly Bom[]>;
  /** The components of `quantity` units at every level of active versions. */
  explodeBom(variantId: string, quantity: number): AsyncResult<BomExplosion>;
  /** The bills of materials the variant goes into, every level up. */
  whereUsed(variantId: string): AsyncResult<readonly BomUse[]>;
  /** Creates a work center or changes one; needs `manufacturing.manage`. */
  saveWorkCenter(
    input: WorkCenterInput,
    workCenterId?: string,
  ): AsyncResult<WorkCenter>;
  workCenters(): AsyncResult<readonly WorkCenter[]>;
  /** A draft order numbered `MO-2026-0001`; needs `manufacturing.write`. */
  createOrder(
    input: ProductionOrderInput<F>,
  ): AsyncResult<ProductionOrderDetail<F>>;
  /**
   * Copies the routing and allocates the components; fails with
   * `PRODUCTION_ORDER_SHORTAGE` when one would go on backorder, unless
   * `allowShortage`.
   */
  release(
    orderId: string,
    options?: { readonly allowShortage?: boolean },
  ): AsyncResult<ProductionOrderDetail<F>>;
  /** Starts an operation; schedules its inspection template. */
  startOperation(operationId: string): AsyncResult<ProductionOrderDetail<F>>;
  /** Finishes an operation; `minutes` defaults to the time since its start. */
  finishOperation(
    operationId: string,
    minutes?: number,
  ): AsyncResult<ProductionOrderDetail<F>>;
  /** Takes a component from stock; `detail` picks the bin, lot or serials. */
  recordConsumption(
    orderId: string,
    variantId: string,
    quantity: number,
    detail?: StockDetail,
  ): AsyncResult<ProductionOrderDetail<F>>;
  /**
   * Backflushes the components not recorded, receives `produced` into stock at
   * component plus labor cost and links the output lot to the lots taken.
   */
  complete(
    orderId: string,
    produced: number,
    options?: { readonly scrap?: number; readonly lot?: ProductionOutputLot },
  ): AsyncResult<ProductionOrderDetail<F>>;
  /** Releases the allocations and returns what was consumed to stock. */
  cancel(
    orderId: string,
    reason?: string,
  ): AsyncResult<ProductionOrderDetail<F>>;
  getOrder(orderId: string): AsyncResult<ProductionOrderDetail<F>>;
  listOrders(
    options?: ProductionOrderListOptions,
  ): AsyncResult<readonly ProductionOrder<F>[]>;
  /** The lots a lot was made from (`down`, the default) or went into (`up`). */
  lotGenealogy(
    lotId: string,
    direction?: "up" | "down",
  ): AsyncResult<LotGenealogy>;
  /** Every lot, stock, document and order a recall of the lot reaches. */
  lotRecall(lotId: string): AsyncResult<LotRecall>;
  /**
   * What to produce or buy within `horizonDays` (default 30), every level
   * netted.
   */
  requirements(horizonDays?: number): AsyncResult<MaterialRequirements>;
  /** Turns suggestions into draft production and purchase orders. */
  createFromRequirements(
    items: readonly RequirementItem[],
  ): AsyncResult<RequirementDocuments<F>>;
}

export interface ManufacturingOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the production orders' extra columns
   * (`blocks.manufacturing.options.extraColumns`), keyed by database name.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Manufacturing<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const optionalNum = (value: unknown): number | undefined =>
  value === null || value === undefined || value === ""
    ? undefined
    : Number(value);

const optionalCurrencyMoney = (
  amount: unknown,
  currency: unknown,
  field: string,
): Money | undefined =>
  typeof currency === "string" && currency !== ""
    ? optionalMoneyOf(amount, currency, field)
    : undefined;

function bomOf(value: unknown, fn: string): Bom {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    variantId: textOf(row["variantId"]),
    version: Number(row["version"]),
    status: enumOrThrow(
      row["status"],
      BOM_STATUSES,
      "bill of materials status",
    ),
    quantity: Number(row["quantity"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("note", optionalText(row["note"])),
    ...optional("activatedAt", optionalInstant(row["activatedAt"])),
  };
}

function bomDetailOf(value: unknown, fn: string): BomDetail {
  const row = recordOf(value, fn);

  return {
    ...bomOf(row, fn),
    components: recordsOf(row["components"], fn).map((c) => ({
      id: textOf(c["id"]),
      variantId: textOf(c["variantId"]),
      quantity: Number(c["quantity"]),
      scrapBps: Number(c["scrapBps"]),
      position: Number(c["position"]),
      ...optional("operationId", optionalText(c["operationId"])),
    })),
    operations: recordsOf(row["operations"], fn).map((o) => ({
      id: textOf(o["id"]),
      sequence: Number(o["sequence"]),
      workCenterId: textOf(o["workCenterId"]),
      title: textOf(o["title"]),
      setupMinutes: Number(o["setupMinutes"]),
      runMinutesPerUnit: Number(o["runMinutesPerUnit"]),
      ...optional("instructionsNodeId", optionalText(o["instructionsNodeId"])),
      ...optional("inspectionTemplate", optionalText(o["inspectionTemplate"])),
    })),
  };
}

function workCenterOf(value: unknown, fn: string): WorkCenter {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    hoursPerDay: Number(row["hoursPerDay"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("assetId", optionalText(row["assetId"])),
    ...optional(
      "costRate",
      optionalCurrencyMoney(row["costRate"], row["currency"], "costRate"),
    ),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
  };
}

const optionalDate = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string" && value !== ""
    ? temporal().PlainDate.from(value)
    : undefined;

function orderOf(value: unknown, fn: string): ProductionOrder {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    number: textOf(row["number"]),
    variantId: textOf(row["variantId"]),
    bomId: textOf(row["bomId"]),
    quantity: Number(row["quantity"]),
    locationId: textOf(row["locationId"]),
    status: enumOrThrow(
      row["status"],
      PRODUCTION_ORDER_STATUSES,
      "production order status",
    ),
    producedQuantity: Number(row["producedQuantity"]),
    scrapQuantity: Number(row["scrapQuantity"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    ...optional("dueOn", optionalDate(row["dueOn"])),
    ...optional("outputLotId", optionalText(row["outputLotId"])),
    ...optional(
      "materialCost",
      optionalCurrencyMoney(
        row["materialCost"],
        row["currency"],
        "materialCost",
      ),
    ),
    ...optional(
      "laborCost",
      optionalCurrencyMoney(row["laborCost"], row["currency"], "laborCost"),
    ),
    ...optional("note", optionalText(row["note"])),
    ...optional("releasedAt", optionalInstant(row["releasedAt"])),
    ...optional("startedAt", optionalInstant(row["startedAt"])),
    ...optional("completedAt", optionalInstant(row["completedAt"])),
    ...optional("canceledAt", optionalInstant(row["canceledAt"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function orderDetailOf(value: unknown, fn: string): ProductionOrderDetail {
  const row = recordOf(value, fn);

  return {
    ...orderOf(row, fn),
    operations: recordsOf(row["operations"], fn).map((o) => ({
      id: textOf(o["id"]),
      sequence: Number(o["sequence"]),
      workCenterId: textOf(o["workCenterId"]),
      title: textOf(o["title"]),
      plannedMinutes: Number(o["plannedMinutes"]),
      status: enumOrThrow(
        o["status"],
        PRODUCTION_OPERATION_STATUSES,
        "production operation status",
      ),
      ...optional("operationId", optionalText(o["operationId"])),
      ...optional("startedAt", optionalInstant(o["startedAt"])),
      ...optional("finishedAt", optionalInstant(o["finishedAt"])),
      ...optional("operatorId", optionalText(o["operatorId"])),
      ...optional("minutes", optionalNum(o["minutes"])),
      ...optional("inspectionId", optionalText(o["inspectionId"])),
    })),
    components: recordsOf(row["components"], fn).map((c) => ({
      componentId: textOf(c["componentId"]),
      variantId: textOf(c["variantId"]),
      quantity: Number(c["quantity"]),
      allocated: Number(c["allocated"]),
      backordered: Number(c["backordered"]),
      consumed: Number(c["consumed"]),
    })),
    consumptions: recordsOf(row["consumptions"], fn).map((c) => ({
      id: textOf(c["id"]),
      variantId: textOf(c["variantId"]),
      quantity: Number(c["quantity"]),
      movementId: textOf(c["movementId"]),
      createdAt: requiredInstant(c["createdAt"], "createdAt"),
      ...optional("lotId", optionalText(c["lotId"])),
      ...optional("serial", optionalText(c["serial"])),
      ...optional(
        "cost",
        optionalCurrencyMoney(c["cost"], c["currency"], "cost"),
      ),
    })),
  };
}

function traceLotOf(row: Record<string, unknown>): TraceLot {
  return {
    lotId: textOf(row["lotId"]),
    code: textOf(row["code"]),
    variantId: textOf(row["variantId"]),
    ...optional("expiresOn", optionalText(row["expiresOn"])),
  };
}

function genealogyOf(value: unknown): LotGenealogy {
  const fn = "lot_genealogy";
  const row = recordOf(value, fn);

  return {
    lotId: textOf(row["lotId"]),
    direction: row["direction"] === "up" ? "up" : "down",
    lots: recordsOf(row["lots"], fn).map((lot) => ({
      ...traceLotOf(lot),
      level: Number(lot["level"]),
      fromLotId: textOf(lot["fromLotId"]),
      orderId: textOf(lot["orderId"]),
      quantity: Number(lot["quantity"]),
    })),
  };
}

function recallOf(value: unknown): LotRecall {
  const fn = "lot_recall";
  const row = recordOf(value, fn);

  return {
    lotId: textOf(row["lotId"]),
    lots: recordsOf(row["lots"], fn).map(traceLotOf),
    stock: recordsOf(row["stock"], fn).map((s) => ({
      lotId: textOf(s["lotId"]),
      variantId: textOf(s["variantId"]),
      locationId: textOf(s["locationId"]),
      onHand: Number(s["onHand"]),
      ...optional("binId", optionalText(s["binId"])),
    })),
    documents: recordsOf(row["documents"], fn).map((d) => ({
      referenceType: textOf(d["referenceType"]),
      referenceId: textOf(d["referenceId"]),
      lotId: textOf(d["lotId"]),
      variantId: textOf(d["variantId"]),
      quantity: Number(d["quantity"]),
      at: requiredInstant(d["at"], "at"),
    })),
    orders: recordsOf(row["orders"], fn).map((o) => ({
      orderId: textOf(o["orderId"]),
      number: textOf(o["number"]),
      status: enumOrThrow(
        o["status"],
        PRODUCTION_ORDER_STATUSES,
        "production order status",
      ),
      variantId: textOf(o["variantId"]),
      ...optional("outputLotId", optionalText(o["outputLotId"])),
    })),
  };
}

function requirementsOf(value: unknown): MaterialRequirements {
  const fn = "material_requirements";
  const row = recordOf(value, fn);

  return {
    organizationId: textOf(row["organizationId"]),
    horizonDays: Number(row["horizonDays"]),
    items: recordsOf(row["items"], fn).map((item) => ({
      variantId: textOf(item["variantId"]),
      action: enumOrThrow(
        item["action"],
        REQUIREMENT_ACTIONS,
        "requirement action",
      ),
      quantity: Number(item["quantity"]),
      available: Number(item["available"]),
      incoming: Number(item["incoming"]),
      planned: Number(item["planned"]),
      demand: Number(item["demand"]),
      ...optional("bomId", optionalText(item["bomId"])),
      ...optional("reorderPoint", optionalNum(item["reorderPoint"])),
    })),
  };
}

function bomArg(input: BomInput): Record<string, unknown> {
  return {
    quantity: input.quantity ?? 1,
    note: input.note ?? null,
    components: input.components.map((c) => ({
      variantId: c.variantId,
      quantity: c.quantity,
      scrapBps: c.scrapBps ?? 0,
      operation: c.operation ?? null,
    })),
    operations: (input.operations ?? []).map((o) => ({
      sequence: o.sequence,
      workCenterId: o.workCenterId,
      title: o.title,
      setupMinutes: o.setupMinutes ?? 0,
      runMinutesPerUnit: o.runMinutesPerUnit ?? 0,
      instructionsNodeId: o.instructionsNodeId ?? null,
      inspectionTemplate: o.inspectionTemplate ?? null,
    })),
  };
}

function workCenterArg(input: WorkCenterInput): Record<string, unknown> {
  return {
    ...optional("name", input.name),
    ...optional("assetId", input.assetId),
    ...optional("hoursPerDay", input.hoursPerDay),
    ...optional("archived", input.archived),
    ...(input.costRate === undefined
      ? {}
      : {
          costRate: input.costRate.amount.toString(),
          currency: input.costRate.currency,
        }),
  };
}

function requirementArg(item: RequirementItem): Record<string, unknown> {
  return {
    variantId: item.variantId,
    action: item.action,
    quantity: item.quantity,
    ...optional("dueOn", item.dueOn?.toString()),
    ...optional("locationId", item.locationId),
    ...optional("supplierType", item.supplier?.type),
    ...optional("supplierId", item.supplier?.id),
    ...(item.unitCost === undefined
      ? {}
      : {
          unitCost: item.unitCost.amount.toString(),
          currency: item.unitCost.currency,
        }),
  };
}

/**
 * Manufacturing: versioned bills of materials with routings on work centers,
 * production orders that allocate, consume and receive stock through the
 * inventory block, lot genealogy and material requirements.
 */
export function createManufacturing<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ManufacturingOptions<S>): Manufacturing<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "production order fields",
  );

  const bom = (fn: string) => (value: unknown) => bomDetailOf(value, fn);
  const order = (fn: string) => (value: unknown) => orderDetailOf(value, fn);

  const client: Manufacturing<F> = {
    saveBom: (variantId, input, bomId) =>
      tenant().andThen((organizationId) =>
        call(
          "save_bom",
          {
            tenant: organizationId,
            variant: variantId,
            input: bomArg(input),
            bom_id: bomId ?? null,
          },
          bom("save_bom"),
        ),
      ),
    activateBom: (bomId) =>
      call("activate_bom", { bom_id: bomId }, bom("activate_bom")),
    getBom: (bomId) => call("get_bom", { bom_id: bomId }, bom("get_bom")),
    listBoms: (variantId) =>
      tenant().andThen((organizationId) =>
        call(
          "list_boms",
          { tenant: organizationId, variant: variantId ?? null },
          (value) =>
            recordsOf(value, "list_boms").map((row) => bomOf(row, "list_boms")),
        ),
      ),
    explodeBom: (variantId, quantity) =>
      call(
        "explode_bom",
        { variant_id: variantId, quantity },
        (value): BomExplosion => {
          const row = recordOf(value, "explode_bom");

          return {
            variantId: textOf(row["variantId"]),
            quantity: Number(row["quantity"]),
            lines: recordsOf(row["lines"], "explode_bom").map((line) => ({
              level: Number(line["level"]),
              variantId: textOf(line["variantId"]),
              parentVariantId: textOf(line["parentVariantId"]),
              bomId: textOf(line["bomId"]),
              quantity: Number(line["quantity"]),
              made: line["made"] === true,
            })),
            materials: recordsOf(row["materials"], "explode_bom").map((m) => ({
              variantId: textOf(m["variantId"]),
              quantity: Number(m["quantity"]),
            })),
          };
        },
      ),
    whereUsed: (variantId) =>
      call("bom_where_used", { variant_id: variantId }, (value) =>
        recordsOf(value, "bom_where_used").map((row) => ({
          level: Number(row["level"]),
          bomId: textOf(row["bomId"]),
          variantId: textOf(row["variantId"]),
          version: Number(row["version"]),
          status: enumOrThrow(
            row["status"],
            BOM_STATUSES,
            "bill of materials status",
          ),
          quantity: Number(row["quantity"]),
        })),
      ),
    saveWorkCenter: (input, workCenterId) =>
      tenant().andThen((organizationId) =>
        call(
          "save_work_center",
          {
            tenant: organizationId,
            input: workCenterArg(input),
            work_center_id: workCenterId ?? null,
          },
          (value) => workCenterOf(value, "save_work_center"),
        ),
      ),
    workCenters: () =>
      tenant().andThen((organizationId) =>
        call("list_work_centers", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_work_centers").map((row) =>
            workCenterOf(row, "list_work_centers"),
          ),
        ),
      ),
    createOrder: (input) =>
      tenant().andThen((organizationId) =>
        fields
          .args(input.fields)
          .andThen((checked) =>
            call(
              "create_production_order",
              {
                tenant: organizationId,
                input: {
                  variantId: input.variantId,
                  quantity: input.quantity,
                  ...optional("locationId", input.locationId),
                  ...optional("dueOn", input.dueOn?.toString()),
                  ...optional("bomId", input.bomId),
                  ...optional("note", input.note),
                  ...optional("fields", checked),
                },
              },
              order("create_production_order"),
            ).andThen(fields.row),
          ),
      ),
    release: (orderId, release = {}) =>
      call(
        "release_production_order",
        { order_id: orderId, allow_shortage: release.allowShortage ?? false },
        order("release_production_order"),
      ).andThen(fields.row),
    startOperation: (operationId) =>
      call(
        "start_production_operation",
        { operation_id: operationId },
        order("start_production_operation"),
      ).andThen(fields.row),
    finishOperation: (operationId, minutes) =>
      call(
        "finish_production_operation",
        { operation_id: operationId, minutes: minutes ?? null },
        order("finish_production_operation"),
      ).andThen(fields.row),
    recordConsumption: (orderId, variantId, quantity, detail) =>
      call(
        "record_production_consumption",
        {
          order_id: orderId,
          variant: variantId,
          quantity,
          detail: detailArg(detail),
        },
        order("record_production_consumption"),
      ).andThen(fields.row),
    complete: (orderId, produced, completion = {}) =>
      call(
        "complete_production_order",
        {
          order_id: orderId,
          produced,
          scrap: completion.scrap ?? 0,
          lot: completion.lot === undefined ? null : { ...completion.lot },
        },
        order("complete_production_order"),
      ).andThen(fields.row),
    cancel: (orderId, reason) =>
      call(
        "cancel_production_order",
        { order_id: orderId, reason: reason ?? null },
        order("cancel_production_order"),
      ).andThen(fields.row),
    getOrder: (orderId) =>
      call(
        "get_production_order",
        { order_id: orderId },
        order("get_production_order"),
      ).andThen(fields.row),
    listOrders: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_production_orders",
          {
            tenant: organizationId,
            filter: {
              ...optional("status", list.status),
              ...optional("variantId", list.variantId),
              ...optional("limit", list.limit),
            },
          },
          (value) =>
            recordsOf(value, "list_production_orders").map((row) =>
              orderOf(row, "list_production_orders"),
            ),
        ).andThen(fields.rows),
      ),
    lotGenealogy: (lotId, direction = "down") =>
      call("lot_genealogy", { lot_id: lotId, direction }, genealogyOf),
    lotRecall: (lotId) => call("lot_recall", { lot_id: lotId }, recallOf),
    requirements: (horizonDays = 30) =>
      tenant().andThen((organizationId) =>
        call(
          "material_requirements",
          { tenant: organizationId, horizon_days: horizonDays },
          requirementsOf,
        ),
      ),
    createFromRequirements: (items) =>
      tenant().andThen((organizationId) =>
        call(
          "create_from_requirements",
          { tenant: organizationId, items: items.map(requirementArg) },
          (value) => {
            const row = recordOf(value, "create_from_requirements");

            return {
              productionOrders: recordsOf(
                row["productionOrders"],
                "create_from_requirements",
              ).map((o) => orderDetailOf(o, "create_from_requirements")),
              purchaseOrders: recordsOf(
                row["purchaseOrders"],
                "create_from_requirements",
              ).map((p) => ({ id: textOf(p["id"]) })),
              purchaseRequisitions: recordsOf(
                row["purchaseRequisitions"] ?? [],
                "create_from_requirements",
              ).map((p) => ({ id: textOf(p["id"]) })),
            };
          },
        ).andThen((documents) =>
          fields
            .rows(documents.productionOrders)
            .map((productionOrders) => ({
              productionOrders,
              purchaseOrders: documents.purchaseOrders,
              purchaseRequisitions: documents.purchaseRequisitions,
            })),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "manufacturing",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
