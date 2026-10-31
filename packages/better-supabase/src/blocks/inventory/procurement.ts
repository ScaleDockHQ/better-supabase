import type { Money } from "../../commerce/money.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockCall } from "../shared.ts";

import { compact } from "../sales-shared.ts";
import {
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export const REQUISITION_STATUSES = [
  "pending",
  "approved",
  "rejected",
  "ordered",
  "cancelled",
] as const;

export type RequisitionStatus = (typeof REQUISITION_STATUSES)[number];

export interface RequisitionLineInput {
  readonly variantId: string;
  /** Base units, with up to the variant's `scale` decimals. */
  readonly quantity: number;
  /** A cost per unit to start the purchase order from. */
  readonly unitCost?: Money;
}

export interface RequisitionInput {
  /** Where the goods should arrive. */
  readonly locationId: string;
  readonly lines: readonly RequisitionLineInput[];
  /** A `config.subjects` record for the preferred supplier. */
  readonly supplier?: { readonly type: string; readonly id: string };
  /** Required when a line names a `unitCost`. */
  readonly currency?: string;
  readonly reason?: string;
}

export interface RequisitionLine {
  readonly id: string;
  readonly variantId: string;
  /** Base units as a decimal string. */
  readonly quantity: string;
  /** Minor units in the requisition's currency, when the line names one. */
  readonly unitCost?: bigint;
}

export interface PurchaseRequisition {
  readonly id: string;
  readonly organizationId: string;
  readonly locationId: string;
  readonly supplier?: { readonly type: string; readonly id: string };
  readonly currency?: string;
  readonly status: RequisitionStatus;
  readonly reason?: string;
  readonly requestedBy?: string;
  readonly decidedBy?: string;
  readonly decidedAt?: Temporal.Instant;
  /** The approval request deciding it, with the approvals block. */
  readonly approvalId?: string;
  /** The purchase order it became. */
  readonly purchaseOrderId?: string;
  readonly lines: readonly RequisitionLine[];
  readonly createdAt: Temporal.Instant;
}

/** Purchase requisitions over the `inventory` SQL module. */
export interface InventoryProcurement {
  /**
   * Asks to buy stock for a location. With the approvals block the requisition
   * opens an approval request under the organization's policy. Emits
   * `purchase_requisition.created`.
   */
  requestPurchase(
    organizationId: string,
    input: RequisitionInput,
  ): AsyncResult<PurchaseRequisition>;
  /**
   * Approves or rejects a pending requisition without an approval request.
   * Needs `inventory.purchase`. Emits `purchase_requisition.approved`.
   */
  decidePurchaseRequisition(
    requisitionId: string,
    approve: boolean,
  ): AsyncResult<PurchaseRequisition>;
  /**
   * A draft purchase order from approved requisitions of one location, their
   * lines summed per variant. The supplier and currency default to the ones the
   * requisitions share.
   */
  purchaseOrderFromRequisitions(
    requisitionIds: readonly string[],
    options?: {
      readonly supplier?: { readonly type: string; readonly id: string };
      readonly currency?: string;
    },
  ): AsyncResult<{ readonly id: string }>;
  getPurchaseRequisition(
    requisitionId: string,
  ): AsyncResult<PurchaseRequisition>;
}

function supplierOf(
  type: unknown,
  id: unknown,
): PurchaseRequisition["supplier"] {
  return typeof type === "string" && typeof id === "string"
    ? { type, id }
    : undefined;
}

function requisitionOf(value: unknown): PurchaseRequisition {
  const row = recordOf(value, "purchase requisition");

  return compact<PurchaseRequisition>({
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    locationId: textOf(row["locationId"]),
    status: enumOrThrow(
      row["status"],
      REQUISITION_STATUSES,
      "purchase requisition status",
    ),
    lines: recordsOf(row["lines"], "purchase requisition lines").map((line) => {
      const cost = optionalText(line["unitCost"]);

      return {
        id: textOf(line["id"]),
        variantId: textOf(line["variantId"]),
        quantity: textOf(line["quantity"]),
        ...(cost === undefined ? {} : { unitCost: BigInt(cost) }),
      };
    }),
    supplier: supplierOf(row["supplierType"], row["supplierId"]),
    currency: optionalText(row["currency"]),
    reason: optionalText(row["reason"]),
    requestedBy: optionalText(row["requestedBy"]),
    decidedBy: optionalText(row["decidedBy"]),
    decidedAt: optionalInstant(row["decidedAt"]),
    approvalId: optionalText(row["approvalId"]),
    purchaseOrderId: optionalText(row["purchaseOrderId"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  });
}

export function inventoryProcurement(call: BlockCall): InventoryProcurement {
  return {
    requestPurchase: (organizationId, input) =>
      call(
        "request_purchase",
        {
          tenant: organizationId,
          location: input.locationId,
          lines: input.lines.map((line) => ({
            variantId: line.variantId,
            quantity: line.quantity,
            ...(line.unitCost === undefined
              ? {}
              : { unitCost: line.unitCost.amount.toString() }),
          })),
          supplier_type: input.supplier?.type ?? null,
          supplier_id: input.supplier?.id ?? null,
          currency:
            input.currency ??
            input.lines.find((line) => line.unitCost !== undefined)?.unitCost
              ?.currency ??
            null,
          reason: input.reason ?? null,
        },
        requisitionOf,
      ),
    decidePurchaseRequisition: (requisitionId, approve) =>
      call(
        "decide_purchase_requisition",
        { requisition: requisitionId, approve },
        requisitionOf,
      ),
    purchaseOrderFromRequisitions: (requisitionIds, options = {}) =>
      call(
        "purchase_order_from_requisitions",
        {
          requisitions: requisitionIds,
          supplier_type: options.supplier?.type ?? null,
          supplier_id: options.supplier?.id ?? null,
          currency: options.currency ?? null,
        },
        (value) => ({
          id: textOf(recordOf(value, "purchase_order_from_requisitions")["id"]),
        }),
      ),
    getPurchaseRequisition: (requisitionId) =>
      call(
        "get_purchase_requisition",
        { requisition: requisitionId },
        requisitionOf,
      ),
  };
}
