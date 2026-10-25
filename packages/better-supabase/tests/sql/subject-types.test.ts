import { describe, expect, it } from "vitest";

import {
  SUBJECT_TYPE_PATTERN,
  subjectTypeIdent,
} from "../../src/core/subject-type.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { registeredSubjects } from "../../src/sql/subject-registry.ts";

const RECORDS = {
  "purchase-order": { table: "public.purchase_orders" },
  "time-off-request": { table: "public.time_off_requests" },
};

const sqlOf = (
  modules: readonly string[],
  module: string,
  config: Record<string, unknown> = {},
): string =>
  renderBlocks(modules, {
    subjects: RECORDS,
    // SAFETY: each module takes `on` and its options as plain config here.
    modules: config as never,
  })
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("hyphenated record types", () => {
  it("are record types", () => {
    expect(SUBJECT_TYPE_PATTERN.test("purchase-order")).toBe(true);
    expect(SUBJECT_TYPE_PATTERN.test("purchase_order")).toBe(true);
    expect(SUBJECT_TYPE_PATTERN.test("-order")).toBe(false);
    expect(SUBJECT_TYPE_PATTERN.test("Order")).toBe(false);
    expect(subjectTypeIdent("time-off-request")).toBe("time_off_request");
    expect(registeredSubjects(RECORDS).map((subject) => subject.type)).toEqual([
      "purchase-order",
      "time-off-request",
    ]);
  });

  it("refuses two types that name the same SQL objects", () => {
    expect(() =>
      registeredSubjects({
        "purchase-order": { table: "a" },
        purchase_order: { table: "b" },
      }),
    ).toThrow(
      /"purchase_order" and "purchase-order" name the same SQL objects/u,
    );
  });

  it("render in the modules that read config.records, as SQL string values", () => {
    for (const module of ["tags", "attachments", "relations", "approvals"]) {
      const sql = sqlOf([module, "subjects"], module);

      expect(sql).toContain("'purchase-order'");
    }
  });

  it("let the subject type columns hold them", () => {
    expect(sqlOf(["attachments", "subjects"], "attachments")).toContain(
      `~ '^[a-z][a-z0-9_-]{0,62}$'`,
    );
  });

  it("give unquoted trigger and function names underscores", () => {
    const sql = sqlOf(["field-history", "subjects"], "field-history", {
      "field-history": { on: { "purchase-order": { fields: ["total"] } } },
    });

    expect(sql).toContain(
      'create trigger bsb_field_history_purchase_order after update of "total" on "public"."purchase_orders"',
    );
    expect(sql).not.toContain("bsb_field_history_purchase-order");
  });
});
