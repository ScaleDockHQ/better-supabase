import type { Money } from "../../commerce/money.ts";
import type { StockDetail } from "../../commerce/stock-detail.ts";
import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { JobHandler } from "../queue/types.ts";
import type { BlockOptions } from "../shared.ts";
import type { InventoryCounts } from "./counts.ts";
import type { InventoryProcurement } from "./procurement.ts";
import type { InventoryTracking } from "./tracking.ts";

import { detailArg } from "../../commerce/stock-detail.ts";
import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  isRecord,
  optionalText,
  recordOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { inventoryCounts } from "./counts.ts";
import { inventoryProcurement } from "./procurement.ts";
import { inventoryTracking } from "./tracking.ts";

export const LOCATION_KINDS = ["warehouse", "store", "virtual"] as const;

export type LocationKind = (typeof LOCATION_KINDS)[number];

/**
 * The reasons `adjustStock` accepts. Counts, sales and transfers write their
 * own.
 */
export const ADJUST_REASONS = [
  "adjustment",
  "damage",
  "loss",
  "return",
  "receipt",
  "scrap",
] as const;

export type AdjustReason = (typeof ADJUST_REASONS)[number];

export const PURCHASE_ORDER_STATUSES = [
  "draft",
  "ordered",
  "partially_received",
  "received",
  "cancelled",
] as const;

export type PurchaseOrderStatus = (typeof PURCHASE_ORDER_STATUSES)[number];

export interface InventoryOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the locations' extra columns
   * (`blocks.inventory.options.extraColumns`), keyed by column name. It types
   * and parses `fields` on `saveLocation` and validates the ones it writes.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around any inventory method. */
  readonly hooks?: NoInfer<BlockHooks<Inventory<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** Where a location is. */
export interface LocationAddress {
  readonly line1?: string;
  readonly line2?: string;
  readonly postalCode?: string;
  readonly city?: string;
  readonly region?: string;
  /** A two-letter ISO 3166 code in capitals. */
  readonly country?: string;
}

export interface LocationInput<F extends object = Record<never, never>> {
  /** Updates this location; creates one when left out. */
  readonly id?: string;
  /** Unique within the organization, such as `WH-AMS`. */
  readonly code: string;
  readonly name: string;
  /** Default `warehouse`. */
  readonly kind?: LocationKind;
  /**
   * Values for the extra columns, by column name; the ones left out keep their
   * value.
   */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

export interface SavedLocation<F extends object = Record<never, never>> {
  readonly id: string;
  readonly code: string;
  readonly active: boolean;
  /**
   * The app's extra columns (`options.extraColumns`), by column name; absent
   * without any.
   */
  readonly fields?: Readonly<Record<string, unknown>> & F;
}

/**
 * Quantities are numbers with up to the variant's `scale` decimals, such as
 * `1.25` kilograms.
 */
export interface StockChange {
  readonly movementId: string;
  readonly onHand: number;
  readonly available: number;
}

export interface StockCount {
  /** Null when the count matched on-hand and no movement was written. */
  readonly movementId: string | null;
  readonly delta: number;
  readonly onHand: number;
}

export interface ReserveInput {
  readonly quantity: number;
  /** What holds the stock, such as `cart` or `order`. */
  readonly referenceType?: string;
  readonly referenceId?: string;
  /** Default: 15 minutes from now. */
  readonly expiresAt?: Temporal.Instant;
}

export interface Reservation {
  readonly id: string;
  readonly expiresAt: Temporal.Instant;
  /** Stock still available at the location after this hold. */
  readonly available: number;
}

export interface StockLine {
  readonly variantId: string;
  readonly quantity: number;
}

export interface TransferLine extends StockLine {
  /** The bin, lot or serials to take from the source location. */
  readonly detail?: StockDetail;
}

export interface TransferInput {
  readonly fromLocationId: string;
  readonly toLocationId: string;
  readonly lines: readonly TransferLine[];
  readonly note?: string;
}

export interface PurchaseOrderLine extends StockLine {
  /** The cost per unit, in the order's currency. */
  readonly unitCost: Money;
}

export interface PurchaseOrderInput {
  readonly id?: string;
  /** Where the goods arrive. */
  readonly locationId: string;
  /** A `config.subjects` record for the supplier, such as a company. */
  readonly supplier?: { readonly type: string; readonly id: string };
  readonly currency: string;
  readonly expectedAt?: Temporal.Instant;
  readonly lines: readonly PurchaseOrderLine[];
  readonly note?: string;
}

export interface ReceiptLine extends StockDetail {
  readonly lineId: string;
  readonly quantity: number;
  /**
   * The member state the goods came from (ISO 3166 alpha-2). With the shipments
   * block's Intrastat lines, a receipt line that names one becomes an arrival
   * line.
   */
  readonly country?: string;
  /** The net mass of the delivered units in kilograms, for Intrastat. */
  readonly netMassKg?: number;
}

export interface Receipt {
  readonly status: PurchaseOrderStatus;
  /** Units ordered and not yet received across the order. */
  readonly backordered: number;
  /** The goods receipt this delivery wrote. */
  readonly receiptId?: string;
}

/** `F` types the locations' extra columns, from the `fields` schema. */
export interface Inventory<F extends object = Record<never, never>>
  extends InventoryTracking, InventoryProcurement, InventoryCounts {
  saveLocation(input: {
    organizationId: string;
    input: LocationInput<F>;
  }): AsyncResult<SavedLocation<F>>;
  /** An inactive location takes no new reservations or transfers. */
  setLocationActive(input: {
    locationId: string;
    active: boolean;
  }): AsyncResult<boolean>;
  /**
   * Sets a location's address, or clears it with null. Refused with
   * `INVENTORY_ADDRESS_INVALID` for a key besides the ones of `LocationAddress`
   * or a country that isn't a two-letter capital code.
   */
  setLocationAddress(input: {
    locationId: string;
    address: LocationAddress | null;
  }): AsyncResult<boolean>;
  /** Refused with `INVENTORY_LOCATION_IN_USE` once it has stock history. */
  deleteLocation(locationId: string): AsyncResult<boolean>;
  /**
   * Writes a movement of `quantity` (negative to remove). Emits
   * `stock.adjusted`.
   */
  adjustStock(input: {
    variantId: string;
    locationId: string;
    quantity: number;
    reason: AdjustReason;
    note?: string | undefined;
    detail?: StockDetail | undefined;
  }): AsyncResult<StockChange>;
  /**
   * Sets on-hand to a counted number and writes the difference as a `count`
   * movement. With a bin or lot in `detail`, counts that bucket only.
   */
  countStock(input: {
    variantId: string;
    locationId: string;
    counted: number;
    note?: string | undefined;
    detail?: StockDetail | undefined;
  }): AsyncResult<StockCount>;
  /** Emits `stock.reorder_point_reached` when available stock drops to it. */
  setReorderPoint(input: {
    variantId: string;
    locationId: string;
    reorderPoint: number;
  }): AsyncResult<boolean>;
  /** Holds stock until it is committed, released or expires. */
  reserve(input: {
    variantId: string;
    locationId: string;
    input: ReserveInput;
  }): AsyncResult<Reservation>;
  /** Turns a hold into a `sale` movement. Resolves to the movement id. */
  commitReservation(reservationId: string): AsyncResult<string>;
  /** Resolves to `false` when the hold was already closed. */
  releaseReservation(reservationId: string): AsyncResult<boolean>;
  /** Releases expired holds. Service only. Resolves to the number released. */
  expireReservations(maxRows?: number): AsyncResult<number>;
  createTransfer(input: {
    organizationId: string;
    input: TransferInput;
  }): AsyncResult<{ readonly id: string }>;
  /** Takes the stock out of the source location. */
  shipTransfer(transferId: string): AsyncResult<boolean>;
  /** Puts the stock into the destination location. */
  receiveTransfer(transferId: string): AsyncResult<boolean>;
  /** Returns shipped stock to the source location. */
  cancelTransfer(transferId: string): AsyncResult<boolean>;
  /** Creates or updates a draft purchase order. */
  savePurchaseOrder(input: {
    organizationId: string;
    input: PurchaseOrderInput;
  }): AsyncResult<{ readonly id: string }>;
  /** Marks the order as ordered and counts its lines as incoming stock. */
  placePurchaseOrder(purchaseOrderId: string): AsyncResult<boolean>;
  /** Receives some or all of the ordered units; the rest stay on backorder. */
  receivePurchaseOrder(input: {
    purchaseOrderId: string;
    lines: readonly ReceiptLine[];
  }): AsyncResult<Receipt>;
  cancelPurchaseOrder(purchaseOrderId: string): AsyncResult<boolean>;
  /** The handler for a scheduled job that runs `expireReservations`. */
  readonly job: JobHandler<unknown>;
}

const isTrue = (value: unknown): boolean => value === true;

function stockChangeOf(value: unknown): StockChange {
  const row = recordOf(value, "adjust_stock");

  return {
    movementId: textOf(row["movementId"]),
    onHand: Number(row["onHand"]),
    available: Number(row["available"]),
  };
}

function idOf(fn: string) {
  return (value: unknown): { readonly id: string } => ({
    id: textOf(recordOf(value, fn)["id"]),
  });
}

function maxRowsOf(payload: unknown): number | undefined {
  if (!isRecord(payload)) {
    return undefined;
  }

  const value = payload["maxRows"];

  return typeof value === "number" ? value : undefined;
}

function purchaseLines(
  input: PurchaseOrderInput,
): readonly Record<string, unknown>[] | string {
  const lines: Record<string, unknown>[] = [];

  for (const line of input.lines) {
    if (line.unitCost.currency !== input.currency) {
      return `a line costs ${line.unitCost.currency}, the order is in ${input.currency}`;
    }

    lines.push({
      variantId: line.variantId,
      quantity: line.quantity,
      unitCost: line.unitCost.amount.toString(),
    });
  }

  return lines;
}

/**
 * Locations, a stock ledger, reservations, transfers and purchase orders over
 * the `inventory` SQL module.
 */
export function createInventory<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: InventoryOptions<S>): Inventory<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const fields: BlockFields<F> = blockFields(options.fields, "location fields");
  const call = blockCall(options.transport, options.schema, options.mappers);

  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const expireReservations: Inventory["expireReservations"] = (maxRows) =>
    service("expire_reservations", { max_rows: maxRows ?? null }, Number);

  const inventory: Inventory<F> = {
    saveLocation: ({ organizationId, input }) =>
      AsyncResult.from(() =>
        input.fields === undefined
          ? Promise.resolve(ok(undefined))
          : fields.write({ ...input.fields }),
      )
        .andThen((valid) =>
          call(
            "save_location",
            {
              tenant: organizationId,
              location: input.id ?? null,
              code: input.code,
              name: input.name,
              kind: input.kind ?? null,
              ...(valid === undefined ? {} : { fields: valid }),
            },
            (value) => {
              const row = recordOf(value, "save_location");

              return {
                id: textOf(row["id"]),
                code: textOf(row["code"]),
                active: row["active"] === true,
                ...(isRecord(row["fields"]) ? { fields: row["fields"] } : {}),
              };
            },
          ),
        )
        .andThen((saved): AsyncResult<SavedLocation<F>> => {
          const { fields: extra, ...rest } = saved;

          return extra === undefined
            ? AsyncResult.ok(rest)
            : AsyncResult.from(() => fields.read(extra)).map((value) => ({
                ...rest,
                fields: value,
              }));
        }),
    setLocationActive: ({ locationId, active }) =>
      call("set_location_active", { location: locationId, active }, isTrue),
    setLocationAddress: ({ locationId, address }) =>
      call("set_location_address", { location: locationId, address }, isTrue),
    deleteLocation: (locationId) =>
      call("delete_location", { location: locationId }, isTrue),
    ...inventoryTracking(call),
    ...inventoryCounts(call),
    ...inventoryProcurement(call),
    adjustStock: ({ variantId, locationId, quantity, reason, note, detail }) =>
      call(
        "adjust_stock",
        {
          variant: variantId,
          location: locationId,
          quantity,
          reason,
          note: note ?? null,
          detail: detailArg(detail),
        },
        stockChangeOf,
      ),
    countStock: ({ variantId, locationId, counted, note, detail }) =>
      call(
        "count_stock",
        {
          variant: variantId,
          location: locationId,
          counted,
          note: note ?? null,
          detail: detailArg(detail),
        },
        (value) => {
          const row = recordOf(value, "count_stock");

          return {
            movementId: optionalText(row["movementId"]) ?? null,
            delta: Number(row["delta"]),
            onHand: Number(row["onHand"]),
          };
        },
      ),
    setReorderPoint: ({ variantId, locationId, reorderPoint }) =>
      call(
        "set_reorder_point",
        {
          variant: variantId,
          location: locationId,
          reorder_point: reorderPoint,
        },
        isTrue,
      ),
    reserve: ({ variantId, locationId, input }) =>
      call(
        "reserve_stock",
        {
          variant: variantId,
          location: locationId,
          quantity: input.quantity,
          reference_type: input.referenceType ?? null,
          reference_id: input.referenceId ?? null,
          expires_at: instantArg(input.expiresAt) ?? null,
        },
        (value) => {
          const row = recordOf(value, "reserve_stock");

          return {
            id: textOf(row["id"]),
            expiresAt: requiredInstant(row["expiresAt"], "expiresAt"),
            available: Number(row["available"]),
          };
        },
      ),
    commitReservation: (reservationId) =>
      call("commit_reservation", { reservation: reservationId }, (value) =>
        textOf(recordOf(value, "commit_reservation")["movementId"]),
      ),
    releaseReservation: (reservationId) =>
      call("release_reservation", { reservation: reservationId }, isTrue),
    expireReservations,
    createTransfer: ({ organizationId, input }) =>
      call(
        "create_transfer",
        {
          tenant: organizationId,
          from_location: input.fromLocationId,
          to_location: input.toLocationId,
          lines: input.lines.map((line) => ({
            variantId: line.variantId,
            quantity: line.quantity,
            detail: detailArg(line.detail),
          })),
          note: input.note ?? null,
        },
        idOf("create_transfer"),
      ),
    shipTransfer: (transferId) =>
      call("ship_transfer", { transfer: transferId }, isTrue),
    receiveTransfer: (transferId) =>
      call("receive_transfer", { transfer: transferId }, isTrue),
    cancelTransfer: (transferId) =>
      call("cancel_transfer", { transfer: transferId }, isTrue),
    savePurchaseOrder: ({ organizationId, input }) => {
      const lines = purchaseLines(input);

      if (typeof lines === "string") {
        return AsyncResult.err(
          dbError("invalid_request", lines, {
            hint: "INVENTORY_CURRENCY_INVALID",
          }),
        );
      }

      return call(
        "save_purchase_order",
        {
          tenant: organizationId,
          purchase_order: input.id ?? null,
          location: input.locationId,
          supplier_type: input.supplier?.type ?? null,
          supplier_id: input.supplier?.id ?? null,
          currency: input.currency,
          expected_at: instantArg(input.expectedAt) ?? null,
          lines,
          note: input.note ?? null,
        },
        idOf("save_purchase_order"),
      );
    },
    placePurchaseOrder: (purchaseOrderId) =>
      call("place_purchase_order", { purchase_order: purchaseOrderId }, isTrue),
    receivePurchaseOrder: ({ purchaseOrderId, lines }) =>
      call(
        "receive_purchase_order",
        {
          purchase_order: purchaseOrderId,
          lines: lines.map(
            ({ lineId, quantity, country, netMassKg, ...detail }) => ({
              lineId,
              quantity,
              ...(country === undefined ? {} : { country }),
              ...(netMassKg === undefined ? {} : { netMassKg }),
              ...detailArg(detail),
            }),
          ),
        },
        (value) => {
          const row = recordOf(value, "receive_purchase_order");

          return {
            status: enumOrThrow(
              row["status"],
              PURCHASE_ORDER_STATUSES,
              "purchase order status",
            ),
            backordered: Number(row["backordered"]),
            ...(typeof row["receiptId"] === "string"
              ? { receiptId: row["receiptId"] }
              : {}),
          };
        },
      ),
    cancelPurchaseOrder: (purchaseOrderId) =>
      call(
        "cancel_purchase_order",
        { purchase_order: purchaseOrderId },
        isTrue,
      ),
    job: async (payload) => {
      await expireReservations(maxRowsOf(payload)).orThrow();
    },
  };

  return withBlockHooks(inventory, options.hooks, {
    block: "inventory",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
