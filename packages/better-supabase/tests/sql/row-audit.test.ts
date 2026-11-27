import { describe, expect, it } from "vitest";

import { sqlString } from "../../src/core/template.ts";
import { renderBlocks } from "../../src/sql/index.ts";
import {
  AUDIT_NOT_IMPORT_SUMMARY,
  auditStatementExecute,
  auditStatementTriggers,
} from "../../src/sql/row-audit.ts";

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
      'create constraint trigger bsb_audit after insert or update or delete on better_supabase.tasks deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting(\'better_supabase.import_audit\', true) is distinct from \'summary\') execute function better_supabase.audit_row_change(\'{"ignore":[],"redact":[],"target_type":"task","event_prefix":"task","archive_column":"archived_at"}\');',
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

  it("leaves the tables of a module with audit false alone", () => {
    const sql = renderBlocks(["audit", "tasks"], {
      modules: { tasks: { audit: false } },
    })
      .filter((file) => file.module === "tasks")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("trigger bsb_audit");
    expect(sql).not.toContain("better_supabase.audit(");
  });

  it("leaves a table the app already has to the app's own triggers", () => {
    const sql = renderBlocks(["audit", "tags"], {
      appTables: { tags: {} },
      ownTables: { "better_supabase.tags": "supabase/schemas/010_app.sql" },
    })
      .filter((file) => file.kind === "schema" && file.module === "tags")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("on public.tags deferrable");
    expect(sql).not.toContain("on better_supabase.tags deferrable");
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

    expect(sql).toContain("current_setting('better_supabase.recorded', true)");
    expect(sql).toContain("set_config('better_supabase.recorded'");
  });
});

describe("statement audit triggers", () => {
  it("prints the same statements audit() creates", () => {
    const target = "public.customers";

    const settings = JSON.stringify({
      ignore: [],
      redact: [],
      category: "data",
    });

    const printed = auditStatementTriggers(target, { category: "data" });

    const fromAudit = [
      ...auditStatementExecute().matchAll(/'([^']*(?:''[^']*)*)'/g),
    ]
      .map((match) =>
        match[1]!
          .replaceAll("''", "'")
          .replace("%s", target)
          .replace("%L", sqlString(settings)),
      )
      .map((statement) => `${statement};`)
      .join("\n");

    expect(printed).toBe(fromAudit);
    expect(printed).toContain(AUDIT_NOT_IMPORT_SUMMARY);
    expect(printed).toContain(
      "referencing old table as old_rows new table as new_rows",
    );
    expect(printed).toContain("bsb_audit_stmt_delete");
  });
});
