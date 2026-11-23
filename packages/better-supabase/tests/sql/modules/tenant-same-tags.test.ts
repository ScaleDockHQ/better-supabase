import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/render.ts";
import { sameTenantTagsOf } from "../../../src/sql/table-facts.ts";
import { sameTenantLayoutOf } from "../../helpers/facts.ts";

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

async function render(comments: string): Promise<string> {
  const layout = await sameTenantLayoutOf([{ text: SCHEMA }], ["public"]);
  const texts = [SCHEMA, comments];

  return moduleBody("memberships", {
    modules: { memberships: { options: { sameTenant: { auto: true } } } },
    ...layout,
    sameTenantTags: sameTenantTagsOf(texts, ["public"], layout.foreignKeys),
  })!;
}

describe("same-tenant column tags", () => {
  it("checks both foreign keys by default", async () => {
    const sql = await render("");

    expect(sql).toContain("bsb_same_tenant_project_id");
    expect(sql).toContain("bsb_same_tenant_parent_id");
  });

  it("drops the check of a column tagged same-tenant=false", async () => {
    const sql = await render(
      "comment on column public.tasks.parent_id is '@bsb same-tenant=false';",
    );

    expect(sql).toContain("bsb_same_tenant_project_id");
    expect(sql).not.toContain("bsb_same_tenant_parent_id");
  });

  it("adds the match columns of a tagged column to its check", async () => {
    const plain = await render("");

    const sql = await render(
      "comment on column public.tasks.project_id is '@bsb same-tenant match=region=region';",
    );

    expect(sql).toContain("bsb_same_tenant_project_id");
    expect(sql).not.toBe(plain);
    expect(sql).toContain("region");
  });
});

describe("same-tenant tags and nullable tenant columns", () => {
  const schema = `
create table public.roles (id uuid primary key, organization_id uuid);
create table public.members (
  id uuid primary key,
  organization_id uuid not null,
  role_id uuid references public.roles
);
create table public.projects (id uuid primary key, organization_id uuid not null);
create table public.tasks (
  id uuid primary key,
  organization_id uuid not null,
  project_id uuid references public.projects
);
`;

  const renderWith = async (comments: string): Promise<string> => {
    const layout = await sameTenantLayoutOf([{ text: schema }], ["public"]);

    return moduleBody("memberships", {
      modules: { memberships: { options: { sameTenant: { auto: true } } } },
      ...layout,
      sameTenantTags: sameTenantTagsOf(
        [schema, comments],
        ["public"],
        layout.foreignKeys,
      ),
    })!;
  };

  it("lets a tagged column share rows when the parent tenant column is nullable", async () => {
    const plain = await renderWith("");

    const tagged = await renderWith(
      "comment on column public.members.role_id is '@bsb same-tenant';",
    );

    expect(tagged).toBe(plain);
    expect(tagged).toMatch(/same_tenant\([^)]*'shared'/u);
  });

  it("refuses rows with no tenant when the parent tenant column is not null", async () => {
    const tagged = await renderWith(
      "comment on column public.tasks.project_id is '@bsb same-tenant';",
    );

    expect(tagged).not.toMatch(/bsb_same_tenant_project_id[^;]*'shared'/u);
  });

  it("honours shared=false on a nullable parent", async () => {
    const tagged = await renderWith(
      "comment on column public.members.role_id is '@bsb same-tenant shared=false';",
    );

    expect(tagged).not.toMatch(/bsb_same_tenant_role_id[^;]*'shared'/u);
  });
});

describe("same-tenant derived from composite keys", () => {
  const schema = `
create table public.projects (id uuid primary key, organization_id uuid not null, region text not null, unique (id, region));
create table public.tasks (
  id uuid primary key,
  organization_id uuid not null,
  project_id uuid not null,
  region text not null,
  foreign key (project_id, region) references public.projects (id, region)
);
create table public.notes (
  id uuid primary key,
  organization_id uuid not null,
  project_id uuid,
  region text,
  foreign key (project_id, region) references public.projects (id, region)
);
`;

  it("checks a composite key with its other columns as match pairs", async () => {
    const layout = await sameTenantLayoutOf([{ text: schema }], ["public"]);

    const sql = moduleBody("memberships", {
      modules: { memberships: {} },
      ...layout,
    })!;

    expect(sql).toContain("bsb_same_tenant_project_id");
    expect(sql).toMatch(/bsb_same_tenant_project_id[^;]*'region', 'region'/u);
  });

  it("leaves a composite key with a nullable column to the database", async () => {
    const layout = await sameTenantLayoutOf([{ text: schema }], ["public"]);

    const sql = moduleBody("memberships", {
      modules: { memberships: {} },
      ...layout,
    })!;

    expect(sql).not.toMatch(/on "public"\."notes"/u);
  });
});
