import { describe, expect, it } from "vitest";

import { sameTenantLayout } from "../../../src/sql/foreign-keys.ts";
import { moduleBody } from "../../../src/sql/render.ts";
import { sameTenantTagsOf } from "../../../src/sql/table-facts.ts";

const SCHEMA = `
create table public.projects (id uuid primary key, organization_id uuid not null, region text);
create table public.tasks (
  id uuid primary key,
  organization_id uuid not null,
  region text,
  project_id uuid references public.projects,
  parent_id uuid references public.tasks
);
`;

function render(comments: string): string {
  const layout = sameTenantLayout([{ text: SCHEMA }], ["public"]);
  const texts = [SCHEMA, comments];

  return moduleBody("memberships", {
    modules: { memberships: { options: { sameTenant: { auto: true } } } },
    ...layout,
    sameTenantTags: sameTenantTagsOf(texts, ["public"], layout.foreignKeys),
  })!;
}

describe("same-tenant column tags", () => {
  it("checks both foreign keys by default", () => {
    const sql = render("");

    expect(sql).toContain("bsb_same_tenant_project_id");
    expect(sql).toContain("bsb_same_tenant_parent_id");
  });

  it("drops the check of a column tagged same-tenant=false", () => {
    const sql = render(
      "comment on column public.tasks.parent_id is '@bsb same-tenant=false';",
    );

    expect(sql).toContain("bsb_same_tenant_project_id");
    expect(sql).not.toContain("bsb_same_tenant_parent_id");
  });

  it("adds the match columns of a tagged column to its check", () => {
    const plain = render("");

    const sql = render(
      "comment on column public.tasks.project_id is '@bsb same-tenant match=region=region';",
    );

    expect(sql).toContain("bsb_same_tenant_project_id");
    expect(sql).not.toBe(plain);
    expect(sql).toContain("region");
  });
});
