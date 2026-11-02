import type { AccountingChartFormat } from "better-supabase/blocks/accounting";

/**
 * An `AccountingChartFormat` that reads a semicolon file of `code;name;type;
 * parent` rows (ADR 0159). Parents come before their children, and a bad row
 * throws, which `importChart` reports as an error instead of saving half a
 * chart.
 */
export const exampleChartFormat: AccountingChartFormat = {
  apiVersion: 1,
  key: "example-chart",
  parse(body) {
    return body
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line !== "" && !line.startsWith("#"))
      .map((line) => {
        const [code, name, type, parent] = line.split(";");

        if (
          code === undefined ||
          name === undefined ||
          (type !== "asset" &&
            type !== "liability" &&
            type !== "equity" &&
            type !== "income" &&
            type !== "expense")
        ) {
          throw new TypeError(`bad chart row: ${line}`);
        }

        return {
          code,
          name,
          type,
          ...(parent === undefined || parent === ""
            ? {}
            : { parentCode: parent }),
        };
      });
  },
};
