import type { StockDetail } from "../../commerce/stock-detail.ts";
import type { LineDirection, ReturnDisposition } from "./statuses.ts";

import { detailArg } from "../../commerce/stock-detail.ts";
import {
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  textOf,
} from "../shared.ts";
import { LINE_DIRECTIONS, RETURN_DISPOSITIONS } from "./statuses.ts";

/** The stock a shipment carries, set while it is a draft. */
export interface ShipmentLineInput {
  readonly variantId: string;
  /** The inventory location the stock leaves from. */
  readonly locationId: string;
  /** A decimal in the variant's unit, up to its scale. */
  readonly quantity: number | string;
  /**
   * An open inventory allocation the line fills, such as an order's. Without
   * one the stock leaves as a `sale`.
   */
  readonly allocationId?: string;
  /** The bin, lot or serials the stock leaves from. */
  readonly detail?: StockDetail;
}

/** Stock a recipient sent back. */
export interface ShipmentReturnInput {
  readonly variantId: string;
  /** The inventory location the stock comes back to. */
  readonly locationId: string;
  readonly quantity: number | string;
  readonly disposition: ReturnDisposition;
  /** For `hold`, `binId` names a hold bin at the location. */
  readonly detail?: StockDetail;
}

/** A shipment line: stock out, or a return with its disposition. */
export interface ShipmentLine {
  readonly id: string;
  /** From 1, in the order the lines were added. */
  readonly position: number;
  readonly direction: LineDirection;
  readonly variantId: string;
  readonly locationId: string;
  /** A decimal string, so fractional units keep their precision. */
  readonly quantity: string;
  readonly allocationId?: string;
  /**
   * The bin, lot and serials, plus `parts`: the lots an outbound line took,
   * once it moved.
   */
  readonly detail?: Readonly<Record<string, unknown>>;
  readonly disposition?: ReturnDisposition;
  /** The inventory movement, once the stock moved. */
  readonly movementId?: string;
  readonly movedAt?: Temporal.Instant;
}

/** Parses a line of a shipment's `lines`. */
export function lineOf(row: Record<string, unknown>): ShipmentLine {
  const disposition = optionalText(row["disposition"]);
  const detail = row["detail"];
  const allocationId = optionalText(row["allocationId"]);
  const movementId = optionalText(row["movementId"]);
  const movedAt = optionalInstant(row["movedAt"]);

  return {
    id: textOf(row["id"]),
    position: Number(row["position"]),
    direction: enumOrThrow(row["direction"], LINE_DIRECTIONS, "direction"),
    variantId: textOf(row["variantId"]),
    locationId: textOf(row["locationId"]),
    quantity: textOf(row["quantity"]),
    ...(allocationId === undefined ? {} : { allocationId }),
    ...(isRecord(detail) ? { detail } : {}),
    ...(disposition === undefined
      ? {}
      : {
          disposition: enumOrThrow(
            disposition,
            RETURN_DISPOSITIONS,
            "disposition",
          ),
        }),
    ...(movementId === undefined ? {} : { movementId }),
    ...(movedAt === undefined ? {} : { movedAt }),
  };
}

/** The `lines` argument of `set_shipment_lines`. */
export function linesArg(
  lines: readonly ShipmentLineInput[],
): Record<string, unknown>[] {
  return lines.map((line) => ({
    variantId: line.variantId,
    locationId: line.locationId,
    quantity: String(line.quantity),
    ...(line.allocationId === undefined
      ? {}
      : { allocationId: line.allocationId }),
    ...(line.detail === undefined ? {} : { detail: detailArg(line.detail) }),
  }));
}

/** The `lines` argument of `receive_shipment_return`. */
export function returnsArg(
  lines: readonly ShipmentReturnInput[],
): Record<string, unknown>[] {
  return lines.map((line) => ({
    variantId: line.variantId,
    locationId: line.locationId,
    quantity: String(line.quantity),
    disposition: line.disposition,
    ...(line.detail === undefined ? {} : { detail: detailArg(line.detail) }),
  }));
}
