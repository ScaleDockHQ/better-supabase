import { appTableId, EMPTY_DESIGN, withDesign } from "better-supabase/create";
import { describe, expect, test } from "vitest";

import { addPrimitive, isPrimitiveKind } from "../../lib/primitives";
import { presetSchema } from "./schema-fixture";

const { preset, data } = presetSchema("saas");

describe("primitives", () => {
  test("a table is an empty app table at the corner", () => {
    const { design, name } = addPrimitive(
      EMPTY_DESIGN,
      new Set(),
      "table",
      [10, 20],
    );

    expect(name).toBe("items");
    expect(design.appTables).toEqual({ items: {} });
    expect(design.positions).toEqual({ [appTableId("items")]: [10, 20] });
  });

  test("a lookup table has a unique code and a label", () => {
    const { design, name } = addPrimitive(
      EMPTY_DESIGN,
      new Set(),
      "lookup",
      [0, 0],
    );

    const table = withDesign(data, design, preset).tables.find(
      (each) => each.id === appTableId(name),
    );

    expect(name).toBe("lookups");
    expect(
      table?.columns.find((column) => column.name === "code"),
    ).toMatchObject({ unique: true, nullable: false });
    expect(table?.columns.map((column) => column.name)).toContain("label");
  });

  test("a tree references itself through parent_id", () => {
    const { design, name } = addPrimitive(
      EMPTY_DESIGN,
      new Set(),
      "tree",
      [0, 0],
      "bigint",
    );

    expect(name).toBe("categories");
    expect(design.appTables?.["categories"]).toEqual({
      id: "bigint",
      columns: {
        name: { type: "text", nullable: false },
        parent_id: {
          type: "bigint",
          references: { table: "categories", onDelete: "cascade" },
        },
      },
    });
  });

  test("names never clash", () => {
    const first = addPrimitive(EMPTY_DESIGN, new Set(), "table", [0, 0]);

    const second = addPrimitive(
      first.design,
      new Set([appTableId("items")]),
      "table",
      [0, 0],
    );

    expect(second.name).toBe("items_2");
  });

  test("knows its kinds", () => {
    expect(isPrimitiveKind("lookup")).toBe(true);
    expect(isPrimitiveKind("view")).toBe(false);
  });
});
