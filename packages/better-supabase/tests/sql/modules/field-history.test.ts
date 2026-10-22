import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

const SUBJECTS = {
  deal: { table: "public.deals", tenant: "tenant_id" },
  note: { table: "public.notes" },
};

const sqlOf = (subjects: unknown): string =>
  renderModules(["field-history", "subjects"], {
    subjects: SUBJECTS,
    modules: { "field-history": { options: { subjects } } },
  })
    .filter((file) => file.module === "field-history")
    .map((file) => file.contents)
    .join("\n");

describe("field-history module", () => {
  it("adds a trigger per record type on its watched columns", () => {
    const sql = sqlOf({ deal: ["amount", "stage_id", "amount"] });

    expect(sql).toContain(
      'create trigger bs_field_history_deal after update of "amount", "stage_id" on "public"."deals"',
    );
    expect(sql).toContain(
      `('amount', to_jsonb(old."amount"), to_jsonb(new."amount"))`,
    );
    expect(sql).toContain("where x.old_value is distinct from x.new_value");
  });

  it("renders no trigger without subjects", () => {
    expect(sqlOf(undefined)).not.toContain("create trigger");
  });

  it("checks read access to the record", () => {
    expect(sqlOf({})).toContain('"better_supabase"."can_subject"(');
  });

  it.each([
    ["a list", [], "blocks.field-history.options.subjects must be an object"],
    ["an unknown type", { order: ["total"] }, 'register "order"'],
    ["no columns", { deal: [] }, "non-empty list of column names"],
    ["a bad column", { deal: ["Amount;"] }, "non-empty list of column names"],
    ["not a list", { deal: "amount" }, "non-empty list of column names"],
  ])("rejects %s", (_, subjects, message) => {
    expect(() => sqlOf(subjects)).toThrow(message);
  });
});
