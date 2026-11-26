import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import { SQL_FUNCTION_RENAMES } from "../../src/sql/function-renames.ts";

interface NamingRow {
  from: string;
  to: string;
  kind: string;
  module?: string;
}

const naming = JSON.parse(
  readFileSync(new URL("../../api/naming.json", import.meta.url), "utf-8"),
) as { renames: NamingRow[] };

describe("SQL_FUNCTION_RENAMES", () => {
  it("matches the sqlFunctionName rows in naming.json", () => {
    const rows = naming.renames
      .filter((row) => row.kind === "sqlFunctionName")
      .map((row) => [row.module, row.from, row.to])
      .toSorted((a, b) => String(a[1]).localeCompare(String(b[1])));

    const pairs = SQL_FUNCTION_RENAMES.map((row) => [...row]).toSorted((a, b) =>
      String(a[1]).localeCompare(String(b[1])),
    );

    expect(pairs).toStrictEqual(rows);
  });

  it("never renames a function to a name another row replaces", () => {
    const from = new Set(SQL_FUNCTION_RENAMES.map(([, old]) => old));

    expect(
      SQL_FUNCTION_RENAMES.filter(([, , next]) => from.has(next)),
    ).toStrictEqual([]);
  });
});
