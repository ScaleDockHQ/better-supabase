import type { AsyncResult } from "../../core/result.ts";
import type { BlockCall } from "../shared.ts";

import { recordOf, recordsOf, textOf } from "../shared.ts";

export const INTRASTAT_FLOWS = ["arrival", "dispatch"] as const;

export type IntrastatFlow = (typeof INTRASTAT_FLOWS)[number];

export interface IntrastatLine {
  readonly id: string;
  readonly flow: IntrastatFlow;
  readonly source: "shipment" | "receipt" | "manual";
  /** The goods receipt line an arrival was derived from. */
  readonly receiptLineId: string | null;
  /**
   * The receipt lines a manual line replaced: a manual arrival for the same
   * variant and country wins over the derived one.
   */
  readonly supersedes: readonly string[];
  readonly variantId: string | null;
  readonly tradeCode: string | null;
  readonly country: string | null;
  readonly netMassKg: string | null;
  readonly quantity: string | null;
  /** Minor units of `currency`. */
  readonly value: string | null;
  readonly currency: string | null;
}

export interface IntrastatException {
  /**
   * `INTRASTAT_TRADE_CODE_MISSING`, `INTRASTAT_COUNTRY_MISSING`,
   * `INTRASTAT_NET_MASS_MISSING` or `INTRASTAT_VALUE_MISSING`.
   */
  readonly code: string;
  readonly lineId: string | null;
  readonly shipmentLineId: string | null;
  readonly receiptLineId: string | null;
}

export interface PreparedIntrastat {
  readonly period: string;
  readonly lines: readonly IntrastatLine[];
  readonly exceptions: readonly IntrastatException[];
  /** The manual lines that replaced a derived receipt line. */
  readonly superseded: readonly {
    readonly manualLineId: string;
    readonly receiptLineId: string;
  }[];
}

export interface ManualIntrastatLine {
  readonly id?: string;
  readonly period: string;
  readonly flow: IntrastatFlow;
  readonly country: string;
  readonly netMassKg: number | string;
  readonly quantity: number | string;
  readonly value: bigint | string;
  readonly currency?: string;
  readonly variantId?: string;
  readonly tradeCode?: string;
}

export interface ShipmentsIntrastat {
  /**
   * Re-derives a month's lines from the shipments moved and the goods receipts
   * received in it and lists the lines that miss a trade code, country, net
   * mass or value. Manual lines stay as they are.
   */
  prepareIntrastat(period: string): AsyncResult<PreparedIntrastat>;
  saveIntrastatLine(
    input: ManualIntrastatLine,
  ): AsyncResult<{ readonly id: string }>;
  deleteIntrastatLine(lineId: string): AsyncResult<boolean>;
}

const nullable = (value: unknown): string | null =>
  value === null || value === undefined ? null : String(value);

const lineOf = (value: unknown): IntrastatLine => {
  const row = recordOf(value, "prepare_intrastat");

  return {
    id: textOf(row["id"]),
    flow: row["flow"] === "arrival" ? "arrival" : "dispatch",
    source:
      row["source"] === "manual" || row["source"] === "receipt"
        ? row["source"]
        : "shipment",
    receiptLineId: nullable(row["receiptLineId"]),
    supersedes: Array.isArray(row["supersedes"])
      ? row["supersedes"].map(String)
      : [],
    variantId: nullable(row["variantId"]),
    tradeCode: nullable(row["tradeCode"]),
    country: nullable(row["country"]),
    netMassKg: nullable(row["netMassKg"]),
    quantity: nullable(row["quantity"]),
    value: nullable(row["value"]),
    currency: nullable(row["currency"]),
  };
};

/** The Intrastat calls of the shipments client. */
export function shipmentsIntrastat(
  call: BlockCall,
  tenant: () => AsyncResult<string>,
): ShipmentsIntrastat {
  return {
    prepareIntrastat: (period) =>
      tenant().andThen((organizationId) =>
        call(
          "prepare_intrastat",
          { tenant: organizationId, period },
          (value) => {
            const row = recordOf(value, "prepare_intrastat");

            return {
              period: textOf(row["period"]),
              lines: recordsOf(row["lines"], "prepare_intrastat").map(lineOf),
              exceptions: recordsOf(row["exceptions"], "prepare_intrastat").map(
                (item) => ({
                  code: textOf(item["code"]),
                  lineId: nullable(item["lineId"]),
                  shipmentLineId: nullable(item["shipmentLineId"]),
                  receiptLineId: nullable(item["receiptLineId"]),
                }),
              ),
              superseded: recordsOf(
                row["superseded"] ?? [],
                "prepare_intrastat",
              ).map((item) => ({
                manualLineId: textOf(item["manualLineId"]),
                receiptLineId: textOf(item["receiptLineId"]),
              })),
            };
          },
        ),
      ),
    saveIntrastatLine: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_intrastat_line",
          {
            tenant: organizationId,
            line: input.id ?? null,
            attrs: {
              period: input.period,
              flow: input.flow,
              country: input.country,
              netMassKg: String(input.netMassKg),
              quantity: String(input.quantity),
              value: String(input.value),
              currency: input.currency,
              variantId: input.variantId,
              tradeCode: input.tradeCode,
            },
          },
          (value) => ({
            id: textOf(recordOf(value, "save_intrastat_line")["id"]),
          }),
        ),
      ),
    deleteIntrastatLine: (lineId) =>
      call("delete_intrastat_line", { line: lineId }, (v) => v === true),
  };
}
