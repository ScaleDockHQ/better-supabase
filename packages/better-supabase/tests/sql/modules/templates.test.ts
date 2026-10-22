import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (modules: readonly string[], layout: Layout = {}): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "templates")
    .map((file) => file.contents)
    .join("\n");

describe("templates module", () => {
  it("keeps one default per tenant, type and language, and one draft per template", () => {
    const sql = sqlOf(["templates"]);
    expect(sql).toContain(
      `("tenant_id", "type", "language") nulls not distinct where "is_default"`,
    );
    expect(sql).toContain(
      `("tenant_id", "key") nulls not distinct where "key" is not null`,
    );
    expect(sql).toContain("TEMPLATE_NO_DRAFT");
    expect(sql).toContain("forked_from_version");
  });

  it("records template.published and template.applied in the outbox when it is installed", () => {
    const without = sqlOf(["templates"]);
    expect(without).not.toContain("'template.applied'");
    const sql = sqlOf(["outbox", "templates"]);
    expect(sql).toContain("'template.published'");
    expect(sql).toContain("'template.applied'");
  });

  it("only attaches workflows when workflow-editor is installed", () => {
    const without = sqlOf(["templates"]);
    expect(without).not.toContain("template_workflows");
    expect(without).not.toContain("attach_template_workflow");
    const sql = sqlOf(["workflow-editor", "templates"]);
    expect(sql).toContain(`"better_supabase"."template_workflows"`);
    expect(sql).toContain("attach_template_workflow");
    expect(sql).toContain("TEMPLATE_WORKFLOW_INPUT_INVALID");
    expect(sql).not.toContain("jsonschema_validation_errors");
  });

  it("checks workflow inputs with pg_jsonschema when jsonb-schemas is installed", () => {
    const sql = sqlOf(["workflow-editor", "jsonb-schemas", "templates"]);
    expect(sql).toContain("extensions.jsonschema_validation_errors(");
  });

  it("keeps sync_templates and the input check to the service role", () => {
    const sql = sqlOf(["workflow-editor", "templates"]);
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."sync_templates"\(jsonb\) to service_role;/,
    );
    expect(sql).not.toMatch(
      /grant execute on function "better_supabase"\."sync_templates"\(jsonb\) to authenticated/,
    );
    expect(sql).not.toMatch(
      /grant execute on function "better_supabase"\."template_workflow_input_errors"\([^)]*\) to authenticated/,
    );
  });

  it("checks templates.apply before applying", () => {
    const sql = sqlOf(["templates"]);
    expect(sql).toContain("'templates.apply'");
    expect(sql).toContain("'templates.manage'");
    expect(sql).toContain("TEMPLATE_NOT_PUBLISHED");
  });
});
