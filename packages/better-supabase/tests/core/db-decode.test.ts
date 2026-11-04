import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { schema } from "../fixtures/generated-camel.ts";

const executor = {
  name: "none",
  execute: () => {
    throw new Error("not called");
  },
};

const db = defineSupabase(schema).connect(executor);

describe("db.$decode", () => {
  it("renames database columns to the configured casing", () => {
    const result = db.$decode("tags").row({ id: "t1", created_at: "x" });

    expect(result.ok && result.data).toMatchObject({
      id: "t1",
      createdAt: "x",
    });
  });

  it("returns a validation error for a value that is not an object", () => {
    const result = db.$decode("tags").row(null);

    expect(!result.ok && result.error.kind).toBe("validation");
  });

  it("decodes a list and reports a value that is not a list", () => {
    const rows = db.$decode("tags").rows([{ id: "a" }, { id: "b" }]);

    expect(rows.ok && rows.data.map((row) => row.id)).toEqual(["a", "b"]);
    expect(db.$decode("tags").rows({}).ok).toBe(false);
  });

  it("throws for an unknown table", () => {
    // @ts-expect-error the table does not exist
    expect(() => db.$decode("nope")).toThrow(/unknown table/);
  });
});
