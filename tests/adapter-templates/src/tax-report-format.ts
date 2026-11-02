import type {
  TaxReport,
  TaxReportFormat,
} from "better-supabase/blocks/accounting";

import { AsyncResult, ok } from "better-supabase";

const formatAmount = (minor: bigint): string => {
  const negative = minor < 0n;
  const digits = (negative ? -minor : minor).toString().padStart(3, "0");

  return `${negative ? "-" : ""}${digits.slice(0, -2)}.${digits.slice(-2)}`;
};

/**
 * A `TaxReportFormat` that writes one CSV row per report box. Replace the
 * columns with your country's return. Keep it pure: the same report gives the
 * same bytes, so a filed return can be checked later.
 */
export const exampleTaxReportFormat: TaxReportFormat = {
  apiVersion: 1,
  name: "example-box-csv",
  render: (report: TaxReport) =>
    AsyncResult.from(() => {
      const rows = report.boxes.map(
        (box) =>
          `${box.box};${formatAmount(box.base)};${formatAmount(box.tax)}`,
      );

      return Promise.resolve(
        ok({
          contentType: "text/csv",
          filename: `tax-${report.since.toString()}-${report.until.toString()}.csv`,
          body: ["box;base;tax", ...rows, ""].join("\n"),
        }),
      );
    }),
};
