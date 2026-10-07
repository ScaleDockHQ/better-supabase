import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { moduleBody } from "../../../src/sql/registry.ts";

const body = (
  sameTenant: unknown,
  tenant: NonNullable<ModulesConfig["tenant"]> = {},
) =>
  moduleBody("tenant", {
    modules: { tenant: { ...tenant, options: { sameTenant } } },
  })!;

describe("tenant module sameTenant", () => {
  it("writes one same_tenant trigger per entry", () => {
    const sql = body([
      { table: "public.tasks", column: "project_id", references: "projects" },
      {
        table: "app.template_settings",
        column: "template_id",
        tenant: "workspace_id",
        references: {
          table: "app.templates",
          column: "key",
          tenant: "owner_workspace",
          where: "{row}.kind = 'task'",
        },
      },
    ]);
    expect(sql).toContain(
      "create or replace function better_supabase.same_tenant()",
    );
    expect(sql).toContain("hint = 'TENANT_MISMATCH'");
    expect(sql).toContain(
      `create trigger "bs_same_tenant_project_id" before insert or update of "project_id", "organization_id" on "public"."tasks"
  for each row execute function better_supabase.same_tenant('project_id', 'organization_id', '"public"."projects"', 'id', 'organization_id');`,
    );
    expect(sql).toContain(
      `create trigger "bs_same_tenant_template_id" before insert or update of "template_id", "workspace_id" on "app"."template_settings"
  for each row execute function better_supabase.same_tenant('template_id', 'workspace_id', '"app"."templates"', 'key', 'owner_workspace', 'p.kind = ''task''');`,
    );
  });

  it("defaults the tenant column to the memberships one", () => {
    const sql = body(
      [{ table: "notes", column: "deal_id", references: "deals" }],
      {
        mode: "adopt",
        tables: { memberships: "public.team_members" },
        columns: { memberships: { tenant: "team_id" } },
      },
    );
    expect(sql).toContain(
      `before insert or update of "deal_id", "team_id" on "public"."notes"`,
    );
    expect(sql).toContain(
      `same_tenant('deal_id', 'team_id', '"public"."deals"', 'id', 'team_id')`,
    );
  });

  it("writes nothing without entries and checks their shape", () => {
    expect(moduleBody("tenant", { modules: {} })).not.toContain("same_tenant");
    expect(() => body({ table: "tasks" })).toThrow(/must be a list/);
    expect(() => body([{ table: "tasks", column: "project_id" }])).toThrow(
      /references: "schema.table"/,
    );
    expect(() =>
      body([{ table: "tasks", column: "Project", references: "projects" }]),
    ).toThrow(/sameTenant\[0\]\.column must be a lowercase column name/);
    expect(() =>
      body([
        {
          table: "tasks",
          column: "project_id",
          references: { table: "projects", where: "kind = 'x'" },
        },
      ]),
    ).toThrow(/where must be a condition on \{row\}/);
    expect(() =>
      body([{ table: "tasks", column: "project_id", references: {} }]),
    ).toThrow(/references.table/);
  });
});
