import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/index.ts";

const schemaOf = (
  names: string[],
  options?: Record<string, unknown>,
  module = "tasks",
) =>
  renderBlocks(
    names,
    options === undefined ? {} : { modules: { audit: { options } } },
  )
    .filter((file) => file.kind === "schema" && file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("row audit of block tables", () => {
  it("registers the entity tables of a block when audit is installed", () => {
    expect(schemaOf(["audit", "tasks"])).toContain(
      'create constraint trigger bsb_audit after insert or update or delete on better_supabase.tasks deferrable initially deferred for each row execute function better_supabase.audit_row_change(\'{"ignore":[],"redact":[],"target_type":"task","event_prefix":"task"}\');',
    );
  });

  it("writes static triggers, never a do block, whatever the install order", () => {
    for (const names of [
      ["audit", "tasks"],
      ["tasks", "audit"],
    ]) {
      const sql = schemaOf(names);

      expect(sql).toContain("create constraint trigger bsb_audit");
      expect(sql).not.toMatch(/perform better_supabase\.audit\(/);
    }
  });

  it("registers every table with blockTables all", () => {
    expect(schemaOf(["audit", "tasks"], { blockTables: "all" })).toContain(
      "create trigger bsb_audit after insert or update or delete on",
    );
  });

  it("leaves tables alone without audit or with blockTables none", () => {
    expect(schemaOf(["tasks"])).not.toContain("better_supabase.audit(");
    expect(schemaOf(["audit", "tasks"], { blockTables: "none" })).not.toContain(
      "better_supabase.audit(",
    );
  });

  it("never audits the audit module's own tables", () => {
    expect(schemaOf(["audit"], undefined, "audit")).not.toContain(
      "Row audit for",
    );
  });

  it("skips rows audit_event recorded through the bsb.recorded marker", () => {
    const sql = renderBlocks(["audit"])
      .filter((file) => file.kind === "schema")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("current_setting('bsb.recorded', true)");
    expect(sql).toContain("set_config('bsb.recorded'");
  });
});
