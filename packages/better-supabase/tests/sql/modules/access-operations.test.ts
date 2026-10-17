import { describe, expect, it } from "vitest";

import {
  moduleOperations,
  OPERATIONS,
} from "../../../src/sql/modules/access-model.ts";
import { renderModules } from "../../../src/sql/render.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const operationFn = (sql: string): string => {
  const start = sql.indexOf("better_supabase.operation_permission(op text)");

  return sql.slice(start, sql.indexOf("$$;", start));
};

const accessSql = (
  names: readonly string[],
  layout: Parameters<typeof renderModules>[1] = {},
): string =>
  renderModules(names, layout)
    .filter((file) => file.module === "access" && file.kind === "schema")
    .map((file) => file.contents)
    .join("\n");

describe("OPERATIONS", () => {
  it("keys every operation <module>.<action>", () => {
    for (const name of Object.keys(OPERATIONS)) {
      expect(name).toMatch(/^[a-z][a-z-]*\.[A-Za-z]+$/);
    }
  });

  it("gives each module its actions by name", () => {
    expect(moduleOperations("organizations").update).toBe(
      "organization.update",
    );
    expect(moduleOperations("audit")).toEqual({
      view: "audit.read",
      viewAll: "audit.read",
      revert: "audit.revert",
    });
  });
});

describe("operation_permission", () => {
  it("answers the installed modules' operations after renames", () => {
    const sql = operationFn(
      accessSql(["access", "audit"], {
        modules: { audit: { permissions: { view: "logs.read" } } },
      }),
    );

    expect(sql).toContain("when 'audit.view' then 'logs.read'");
    expect(sql).toContain("when 'audit.revert' then 'audit.revert'");
    expect(sql).not.toContain("'billing.read'");
  });

  it("lets the provider's operations take precedence", () => {
    const sql = operationFn(
      accessSql(["access", "audit"], {
        accessProvider: {
          ...moduleProvider,
          operations: {
            "audit.revert": { permission: "audit.undo" },
            "invoices.void": { permission: "billing.manage" },
          },
        },
      }),
    );

    expect(sql).toContain("when 'audit.revert' then 'audit.undo'");
    expect(sql).toContain("when 'invoices.void' then 'billing.manage'");
  });
});
