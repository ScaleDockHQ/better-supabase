import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it } from "vitest";

import { dryRun } from "../../../src/blocks/imports/define-import.ts";

const columns: StandardSchemaV1<unknown, { name: string }> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) => {
      if (
        typeof value === "object" &&
        value !== null &&
        "name" in value &&
        typeof value.name === "string" &&
        value.name !== ""
      ) {
        return { value: { name: value.name } };
      }

      return { issues: [{ message: "name is required" }] };
    },
  },
};

const definition = {
  source: "contacts",
  columns,
  key: (row: { name: string }) => row.name,
};

describe("import dry run", () => {
  it("returns nothing for an empty file and reports a row that fails", async () => {
    expect(await dryRun(definition, "", {})).toEqual({ rows: [], errors: [] });

    const result = await dryRun(definition, "name,note\nAda,hi\n,missing\n", {
      name: "name",
    });

    expect(result.rows).toEqual([{ name: "Ada" }]);
    expect(result.errors).toEqual([
      { row: 3, message: "Invalid contacts row 3" },
    ]);
  });
});
