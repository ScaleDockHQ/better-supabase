import { describe, expect, it } from "vitest";

import { moduleContext } from "../../src/sql/module-context.ts";
import { runsOverAppTables } from "../../src/sql/module-types.ts";
import { overAppTables } from "../../src/sql/over-app-tables.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { declaredTables } from "../../src/sql/schema-scan.ts";

const SQL = `create table if not exists public.invoices (
  -- the tenant's id (it scopes every row)
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id),
  status text not null default 'draft',
  code text not null unique,
  unique (organization_id, code)
);

create index invoices_status on public.invoices (status);
`;

describe("overAppTables", () => {
  it("turns the create table of an app table into the columns it lacks", () => {
    expect(
      overAppTables(SQL, new Set(["public.invoices"]), {
        "public.invoices": ["id", "status"],
      }),
    )
      .toBe(`-- public.invoices is the app's table: this block adds only the columns it needs.
alter table public.invoices add column if not exists organization_id uuid references public.organizations (id);
alter table public.invoices add column if not exists code text;

create index invoices_status on public.invoices (status);
`);
  });

  it("adds every column when the app's columns are unknown", () => {
    const out = overAppTables(SQL, new Set(["public.invoices"]));

    expect(out).not.toContain("create table");
    expect(out).toContain(
      "add column if not exists id uuid default gen_random_uuid();",
    );
    expect(out).toContain(
      "add column if not exists status text not null default 'draft';",
    );
  });

  it("leaves the tables the block owns", () => {
    expect(overAppTables(SQL, new Set(["public.contacts"]))).toBe(SQL);
  });
});

function rendersAlone(module: string): boolean {
  try {
    renderBlocks([module]);

    return true;
  } catch {
    return false;
  }
}

const ALONE = Object.keys(SQL_MODULES).filter(
  (name) => name !== "pgtap" && rendersAlone(name),
);

const OVER = ALONE.filter((name) => {
  const module = SQL_MODULES[name];

  return module !== undefined && runsOverAppTables(module);
});

const CREATING = ALONE.filter(
  (name) => !OVER.includes(name) && createdAlone(name).length > 0,
);

function tablesOf(module: string): string[] {
  const ctx = moduleContext(module, {}, [module]);

  return Object.keys(SQL_MODULES[module]?.names?.tables ?? {})
    .filter((logical) => ctx.hasTable(logical))
    .map((logical) => {
      const { schema, name } = ctx.tableName(logical);

      return `${schema}.${name}`;
    });
}

function created(module: string, ownTables: Record<string, string>): string[] {
  const files = renderBlocks([module], { ownTables }).filter(
    (file) => file.module === module,
  );

  return declaredTables(
    files.map((file) => ({ text: file.contents })),
    ["public", "better_supabase"],
  );
}

function createdAlone(module: string): string[] {
  const alone = created(module, {});

  return tablesOf(module).filter((table) => alone.includes(table));
}

describe("ctx.owns", () => {
  it("is false for a table the app has, and casts only its typed columns", () => {
    const ctx = moduleContext(
      "tags",
      { ownTables: { "better_supabase.tags": "supabase/schemas/tags.sql" } },
      ["tags"],
    );

    expect(ctx.owns("tags")).toBe(false);
    expect(ctx.owns("taggings")).toBe(true);
    expect(ctx.appOwned).toEqual(["tags"]);
    expect(ctx.manages).toBe(true);
    expect(ctx.cast("tags", "kind", "'label'")).toContain(
      "better_supabase.as_column_type('label'",
    );
    expect(ctx.cast("taggings", "subjectType", "'deal'")).toBe("'deal'");
  });

  it("is true for every table without ownTables", () => {
    const ctx = moduleContext("tags", {}, ["tags"]);

    expect(ctx.owns("tags")).toBe(true);
    expect(ctx.cast("tags", "kind", "'label'")).toBe("'label'");
  });
});

describe("blocks over the app's tables", () => {
  it.each(OVER)("%s creates none of the tables the app has", (module) => {
    const own = Object.fromEntries(
      createdAlone(module).map((table) => [table, "app.sql"]),
    );

    expect(
      created(module, own).filter((table) => Object.hasOwn(own, table)),
    ).toEqual([]);
  });

  it.each(CREATING)("%s refuses to create a table the app has", (module) => {
    const table = createdAlone(module)[0] ?? "";

    expect(() => created(module, { [table]: "app.sql" })).toThrow(
      `creates ${table}, which is already in app.sql`,
    );
  });
});
