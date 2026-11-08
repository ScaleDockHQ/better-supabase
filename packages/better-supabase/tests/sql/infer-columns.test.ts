import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { moduleBody } from "../../src/sql/render.ts";

const TABLE = "public.orgs";

const COLUMNS = ["id", "name", "slug", "created_at", "updated_at"];

const layout = (
  columns: Record<string, string | null> | undefined,
  options: {
    readonly held?: readonly string[] | false;
    readonly view?: boolean;
  } = {},
): BlockSqlLayout => {
  const held = options.held ?? COLUMNS;

  return {
    modules: {
      organizations: {
        tables: { organizations: TABLE },
        ...(columns === undefined
          ? {}
          : { columns: { organizations: columns } }),
      },
    },
    ownTables: { [TABLE]: "supabase/schemas/orgs.sql" },
    ...(options.view === true
      ? { ownViews: { [TABLE]: { updatable: false } } }
      : {}),
    ...(held === false ? {} : { ownColumns: { [TABLE]: held } }),
  };
};

describe("optional columns an app view lacks", () => {
  it("turns the feature off without a null entry", () => {
    const sql = moduleBody("organizations", layout({}, { view: true }))!;

    expect(sql).not.toContain('"deleted_at"');
    expect(sql).not.toContain('"created_by"');
  });

  it("keeps the column when the view has it", () => {
    const sql = moduleBody(
      "organizations",
      layout(
        {},
        { view: true, held: [...COLUMNS, "deleted_at", "created_by"] },
      ),
    )!;

    expect(sql).toContain("deleted_at");
  });

  it("refuses a null entry for a column the view lacks anyway", () => {
    expect(() =>
      moduleBody("organizations", layout({ deletedAt: null }, { view: true })),
    ).toThrow(
      'blocks.organizations.columns.organizations.deletedAt: maps to null, but public.orgs has no "deleted_at" column',
    );
  });

  it("allows a null entry for a column the view has", () => {
    expect(() =>
      moduleBody(
        "organizations",
        layout(
          { deletedAt: null },
          { view: true, held: [...COLUMNS, "deleted_at"] },
        ),
      ),
    ).not.toThrow();
  });

  it("keeps a null entry on a table the app owns, where it stops the block adding the column", () => {
    expect(() =>
      moduleBody("organizations", layout({ deletedAt: null })),
    ).not.toThrow();
  });

  it("leaves the columns alone when the view's columns are unknown", () => {
    expect(() =>
      moduleBody(
        "organizations",
        layout({ deletedAt: null }, { view: true, held: false }),
      ),
    ).not.toThrow();
  });
});

describe("the tenant column", () => {
  const withTenant = (entry: string | undefined): BlockSqlLayout => ({
    blockTenantColumn: "org_id",
    modules: {
      tags: {
        ...(entry === undefined
          ? {}
          : { columns: { tags: { tenant: entry } } }),
      },
    },
  });

  it("fills the tenant column of every block from sql.tenantColumn", () => {
    expect(moduleBody("tags", withTenant(undefined))).toContain('"org_id"');
  });

  it("refuses an entry that repeats sql.tenantColumn", () => {
    expect(() => moduleBody("tags", withTenant("org_id"))).toThrow(
      'blocks.tags.columns.tags.tenant: "org_id" is sql.tenantColumn',
    );
  });

  it("keeps an entry that names another column", () => {
    expect(moduleBody("tags", withTenant("account_id"))).toContain(
      '"account_id"',
    );
  });
});
