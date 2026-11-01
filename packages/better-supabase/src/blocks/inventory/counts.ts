import type { AsyncResult } from "../../core/result.ts";
import type { BlockCall } from "../shared.ts";

import { optionalText, recordOf, textOf } from "../shared.ts";

export const COUNT_STATUSES = ["open", "posted", "cancelled"] as const;

export type CountStatus = (typeof COUNT_STATUSES)[number];

export interface OpenCountInput {
  readonly note?: string;
  /** Counts only these variants. Defaults to everything in stock. */
  readonly variantIds?: readonly string[];
}

export interface CountLineInput {
  readonly variantId: string;
  readonly counted: number | string;
  readonly binId?: string;
  readonly lotId?: string;
  readonly serial?: string;
}

export interface OpenedCount {
  readonly id: string;
  /** Lines snapshotted from the stock on hand. */
  readonly lines: number;
}

export interface CountLine {
  readonly id: string;
  readonly expected: string;
  readonly counted: string;
  readonly variance: string;
}

export interface PostedCount {
  /** False when the count was already posted, which changes nothing. */
  readonly posted: boolean;
  readonly movements: number;
  readonly variance: string;
}

export interface InventoryCounts {
  /** Snapshots the expected stock of a location into a count document. */
  openStockCount(input: {
    organizationId: string;
    locationId: string;
    input?: OpenCountInput | undefined;
  }): AsyncResult<OpenedCount>;
  /** Records a counted quantity; it replaces an earlier line for the position. */
  recordCountLine(input: {
    countId: string;
    input: CountLineInput;
  }): AsyncResult<CountLine>;
  /**
   * Writes one `count` movement per line with a variance, through the stock and
   * ledger path. Posting twice writes nothing the second time.
   */
  postStockCount(countId: string): AsyncResult<PostedCount>;
  cancelStockCount(countId: string): AsyncResult<boolean>;
}

/** The stock count calls of the inventory client. */
export function inventoryCounts(call: BlockCall): InventoryCounts {
  return {
    openStockCount: ({ organizationId, locationId, input = {} }) =>
      call(
        "open_stock_count",
        {
          tenant: organizationId,
          location: locationId,
          attrs: { note: input.note, variantIds: input.variantIds },
        },
        (value) => {
          const row = recordOf(value, "open_stock_count");

          return { id: textOf(row["id"]), lines: Number(row["lines"]) };
        },
      ),
    recordCountLine: ({ countId, input }) =>
      call(
        "record_count_line",
        {
          count: countId,
          attrs: {
            variantId: input.variantId,
            counted: String(input.counted),
            binId: input.binId,
            lotId: input.lotId,
            serial: input.serial,
          },
        },
        (value) => {
          const row = recordOf(value, "record_count_line");

          return {
            id: textOf(row["id"]),
            expected: textOf(row["expected"]),
            counted: textOf(row["counted"]),
            variance: optionalText(row["variance"]) ?? "0",
          };
        },
      ),
    postStockCount: (countId) =>
      call("post_stock_count", { count: countId }, (value) => {
        const row = recordOf(value, "post_stock_count");

        return {
          posted: row["posted"] === true,
          movements: Number(row["movements"] ?? 0),
          variance: optionalText(row["variance"]) ?? "0",
        };
      }),
    cancelStockCount: (countId) =>
      call("cancel_stock_count", { count: countId }, (v) => v === true),
  };
}
