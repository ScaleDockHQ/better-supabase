import { describe, expect, it } from "vitest";

import {
  checkFunctionRenames,
  checkTenantName,
} from "../../../src/sql/pipeline/checks.ts";
import {
  guardBelowHeader,
  renameQualifiers,
} from "../../../src/sql/pipeline/prepare.ts";
import {
  appTableSet,
  ownTablesCreatedBy,
} from "../../../src/sql/pipeline/resolve.ts";

const ctxOf = (parts: object): never => parts as never;

describe("prepare", () => {
  it("renames the parameter qualifiers of renamed functions", () => {
    const ctx = ctxOf({
      functionRenames: () => [["create_organization", "create_workspace"]],
    });

    expect(
      renameQualifiers(
        "select create_organization.name, x.create_organization.y",
        ctx,
      ),
    ).toBe("select create_workspace.name, x.create_organization.y");
  });

  it("keeps the marker lines above the guarded SQL", () => {
    const out = guardBelowHeader("-- header\n\nselect 1;", {});

    expect(out.startsWith("-- header\n")).toBe(true);
    expect(out).toContain("select 1;");
  });

  it("guards a file without a header", () => {
    expect(guardBelowHeader("select 1;", {})).toContain("select 1;");
  });
});

describe("checks", () => {
  it("accepts a layout without a renamed tenant", () => {
    expect(() => {
      checkTenantName([], {});
    }).not.toThrow();
  });

  it("passes when every function rename is used", () => {
    expect(() => {
      checkFunctionRenames(ctxOf({ unusedFunctions: () => [] }));
    }).not.toThrow();
  });

  it("names the unused function renames", () => {
    expect(() => {
      checkFunctionRenames(
        ctxOf({ module: "tasks", unusedFunctions: () => ["a", "b"] }),
      );
    }).toThrow(
      'blocks.tasks.functions: the tasks module writes no function "a", "b"',
    );
  });
});

describe("resolve", () => {
  it("has no app tables when the block does not manage them", () => {
    expect(
      appTableSet(
        ctxOf({ manages: false, appOwned: ["t"], tableName: () => ({}) }),
      ),
    ).toStrictEqual(new Set());
  });

  it("lists the managed app tables as schema.table", () => {
    const ctx = ctxOf({
      manages: true,
      appOwned: ["task"],
      appViews: [],
      tableName: (name: string) => ({ schema: "public", name: `${name}s` }),
    });

    expect(appTableSet(ctx)).toStrictEqual(new Set(["public.tasks"]));
  });

  it("creates no tables over the app without ownTables", () => {
    const ctx = ctxOf({ manages: true });

    expect(ownTablesCreatedBy({ name: "x" } as never, ctx, {})).toStrictEqual(
      new Set(),
    );
  });
});
