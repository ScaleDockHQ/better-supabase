import { describe, expect, it } from "vitest";

import { resolveConfig } from "../../src/config/resolve.ts";
import { moduleLayout } from "../../src/sql/layout.ts";
import { moduleContext } from "../../src/sql/module-context.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const rendered = (module: string, blockTenantColumn?: string): string => {
  try {
    return renderBlocks(
      [module],
      blockTenantColumn === undefined ? {} : { blockTenantColumn },
    )
      .filter((file) => file.module === module)
      .map((file) => file.contents)
      .join("\n");
  } catch {
    return "";
  }
};

describe("sql.tenantColumn", () => {
  it("names the tenant column of every table a block creates", () => {
    const left = Object.keys(SQL_MODULES)
      .filter((module) => module !== "pgtap")
      .filter((module) =>
        rendered(module, "organization_id").includes('"tenant_id"'),
      );

    expect(left).toEqual([]);
  });

  it("changes the SQL of the modules with tenant tables", () => {
    const sql = rendered("quotes", "organization_id");

    expect(sql).toContain('"organization_id" uuid not null,');
    expect(sql).toContain('unique ("organization_id", "number", "revision")');
    expect(rendered("quotes")).toContain('"tenant_id" uuid not null,');
  });

  it("leaves a column the block maps to its mapping", () => {
    const ctx = moduleContext("quotes", {
      blockTenantColumn: "organization_id",
      modules: { quotes: { columns: { lines: { tenant: "org" } } } },
    });

    expect(ctx.colName("quotes", "tenant")).toBe("organization_id");
    expect(ctx.colName("lines", "tenant")).toBe("org");
  });

  it("refuses a name another column of the table has", () => {
    const ctx = moduleContext("quotes", { blockTenantColumn: "parent_id" });

    expect(() => ctx.colName("lines", "tenant")).toThrow(
      /sql\.tenantColumn: "parent_id" is the name of lines\.parent/u,
    );
  });

  it("refuses a name that isn't an identifier", () => {
    expect(() =>
      moduleContext("quotes", { blockTenantColumn: "org id" }),
    ).toThrow(/sql\.tenantColumn/u);
  });

  it("reaches the layout from the config", () => {
    const config = resolveConfig(
      {
        blocks: ["quotes"],
        database: { sql: { tenantColumn: "organization_id" } },
      },
      "/project",
    );

    expect(config.sql.tenantColumn).toBe("organization_id");
    expect(moduleLayout(config).blockTenantColumn).toBe("organization_id");
    expect(
      moduleLayout(resolveConfig({ blocks: ["quotes"] }, "/project")),
    ).not.toHaveProperty("blockTenantColumn");
  });
});
