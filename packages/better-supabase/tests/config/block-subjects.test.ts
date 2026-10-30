import { describe, expect, it } from "vitest";

import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { resolveConfig } from "../../src/config/resolve.ts";

describe("withBlockSubjects", () => {
  it("registers a task as a ranked, searchable subject", () => {
    expect(withBlockSubjects({}, ["tasks"], {})).toEqual({
      task: {
        table: "better_supabase.tasks",
        idType: "uuid",
        tenant: "tenant_id",
        title: "title",
        deletedAt: "archived_at",
        permissions: { read: "tasks.read", write: "tasks.write" },
        rank: { column: "rank", group: "stage_id" },
        search: { title: "title", body: ["identifier", "body"] },
      },
    });
  });

  it("registers products with their default page and the manage key", () => {
    const subjects = withBlockSubjects({}, ["catalog"], {});

    expect(subjects["product"]).toMatchObject({
      url: "/products/{slug}",
      permissions: { read: "catalog.read", write: "catalog.manage" },
      cascade: true,
    });
    expect(subjects["product_variant"]?.title).toBe("sku");
  });

  it("registers the entities of the blocks a block requires", () => {
    expect(
      Object.keys(withBlockSubjects({}, ["inventory"], {})).toSorted(),
    ).toEqual(["ledger_account", "product", "product_variant"]);
  });

  it("names a renamed entity's subject, table and permission keys", () => {
    const subjects = withBlockSubjects({}, ["tasks"], {
      tasks: {
        schema: "app",
        entities: { work_item: { name: "task", url: "/tasks/{identifier}" } },
      },
    });

    expect(subjects).toMatchObject({
      task: {
        table: "app.tasks",
        permissions: { read: "tasks.read", write: "tasks.write" },
        url: "/tasks/{identifier}",
      },
    });
  });

  it("reads table, column and permission overrides", () => {
    const subjects = withBlockSubjects({}, ["employees"], {
      employees: {
        tables: { employees: "hr.staff" },
        columns: { employees: { name: "full_name" } },
        permissions: { read: "staff.view" },
      },
    });

    expect(subjects["employee"]).toMatchObject({
      table: "hr.staff",
      title: "full_name",
      permissions: { read: "staff.view", write: "employees.write" },
      search: { title: "full_name" },
    });
  });

  it("leaves a column mapped to null out of the search", () => {
    const subjects = withBlockSubjects({}, ["tasks"], {
      tasks: { columns: { items: { body: null } } },
    });

    expect(subjects["task"]?.search).toEqual({
      title: "title",
      body: ["identifier"],
    });
  });

  it("sets a url without renaming the entity", () => {
    expect(
      withBlockSubjects({}, ["deals"], {
        deals: { entities: { deal: { url: "/crm/deals" } } },
      })["deal"]?.url,
    ).toBe("/crm/deals");
  });

  it("leaves out an entity with subject: false and a block in custom mode", () => {
    expect(
      withBlockSubjects({}, ["tasks", "employees"], {
        tasks: { entities: { task: { subject: false } } },
        employees: { mode: "custom" },
      }),
    ).toEqual({});
  });

  it("rejects a subjects entry with a type a block registers", () => {
    expect(() =>
      withBlockSubjects({ deal: { table: "public.deals" } }, ["deals"], {}),
    ).toThrow(/the deals block registers "deal" itself/);
  });
});

describe("resolveConfig subjects", () => {
  it("adds block subjects next to the app's own", () => {
    const resolved = resolveConfig(
      {
        blocks: ["tasks"],
        subjects: { invoice: { table: "public.invoices" } },
      },
      "/app",
    );

    expect(Object.keys(resolved.subjects).toSorted()).toEqual([
      "invoice",
      "task",
    ]);
  });

  it("names the tenant column sql.tenantColumn gives every block table", () => {
    const resolved = resolveConfig(
      {
        blocks: {
          ledger: {},
          employees: { columns: { employees: { tenant: "org" } } },
        },
        database: { sql: { tenantColumn: "organization_id" } },
      },
      "/app",
    );

    expect(resolved.subjects["ledger_account"]?.tenant).toBe("organization_id");
    expect(resolved.subjects["employee"]?.tenant).toBe("org");
  });

  it("keeps tenant_id without sql.tenantColumn", () => {
    expect(
      resolveConfig({ blocks: ["ledger"] }, "/app").subjects["ledger_account"]
        ?.tenant,
    ).toBe("tenant_id");
  });
});
