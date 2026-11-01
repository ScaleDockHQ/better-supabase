import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/index.ts";

const dataOf = (
  names: string[],
  options?: Record<string, unknown>,
  module = "tasks",
) =>
  renderBlocks(
    names,
    options === undefined ? {} : { modules: { audit: { options } } },
  )
    .filter((file) => file.kind === "data" && file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("row audit of block tables", () => {
  it("registers the entity tables of a block when audit is installed", () => {
    expect(dataOf(["audit", "tasks"])).toContain(
      "select better_supabase.audit('better_supabase.tasks'",
    );
  });

  it("leaves tables alone without audit or with blockTables none", () => {
    expect(dataOf(["tasks"])).not.toContain("better_supabase.audit(");
    expect(dataOf(["audit", "tasks"], { blockTables: "none" })).not.toContain(
      "better_supabase.audit(",
    );
  });

  it("never audits the audit module's own tables", () => {
    expect(dataOf(["audit"], undefined, "audit")).not.toContain(
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
