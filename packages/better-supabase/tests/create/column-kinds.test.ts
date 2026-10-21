import { describe, expect, it } from "vitest";

import {
  columnLabel,
  COLUMN_KINDS,
  KIND_GROUPS,
  kindById,
  kindOf,
  setColumnKind,
  withKind,
  addTable,
  setColumn,
} from "../../src/create/index.ts";

const kind = (id: string) => {
  const found = kindById(id);

  if (found === undefined) {
    throw new Error(`no kind ${id}`);
  }

  return found;
};

describe("column kinds", () => {
  it("every kind is in a group and reads back as itself", () => {
    for (const each of COLUMN_KINDS) {
      expect(KIND_GROUPS).toContain(each.group);
    }

    for (const each of COLUMN_KINDS.filter((one) => one.drawn !== true)) {
      expect(kindOf(each.column).id).toBe(each.id);
    }
  });

  it("a reference to another table reads as a link", () => {
    expect(kindOf({ type: "uuid", references: { table: "projects" } }).id).toBe(
      "reference",
    );
  });

  it("withKind keeps what fits and drops the rest", () => {
    expect(
      withKind(
        { type: "text", nullable: false, max: 80, comment: "Who" },
        kind("email"),
      ),
    ).toEqual({
      type: "text",
      nullable: false,
      max: 80,
      comment: "Who",
      format: "email",
    });

    expect(
      withKind({ type: "text", max: 80, default: "'x'" }, kind("rating")),
    ).toEqual({ type: "integer", format: "rating" });

    expect(
      withKind(
        { type: "text", options: ["a", "b", "c"] },
        kind("multi_select"),
      ),
    ).toEqual({ type: "text[]", options: ["a", "b", "c"] });
  });

  it("currency becomes a minor-unit column and a currency code", () => {
    const design = setColumn(addTable({}, "orders"), "orders", "total", {
      type: "integer",
      nullable: false,
    });

    const result = setColumnKind(design, "orders", "total", kind("currency"));

    expect(result.name).toBe("total_minor");
    expect(result.design.appTables?.["orders"]?.columns).toEqual({
      total_minor: { type: "bigint", nullable: false, format: "currency" },
      total_currency: { type: "text", nullable: false, min: 3, max: 3 },
    });
  });

  it("labels name what a column is beyond its type", () => {
    expect(columnLabel({ type: "text", format: "long_text" })).toBe(
      "long text",
    );
    expect(columnLabel({ type: "text[]", options: ["a"] })).toBe(
      "multi-select",
    );
    expect(columnLabel({ type: "bigint", identity: true })).toBe("autonumber");
    expect(
      columnLabel({ type: "uuid", references: { table: "auth.users" } }),
    ).toBe("person");
    expect(columnLabel({ type: "text" })).toBeUndefined();
  });
});
