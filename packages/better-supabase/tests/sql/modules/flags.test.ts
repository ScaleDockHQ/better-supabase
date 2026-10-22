import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (names: readonly string[]): string =>
  renderBlocks(names)
    .filter((file) => file.contents.includes("flag_overrides"))
    .map((file) => file.contents)
    .join("\n");

describe("flags module", () => {
  it("writes the tables, the bucket and the evaluation functions", () => {
    const sql = sqlOf(["flags"]);
    expect(sql).toMatch(/create table if not exists \S+flags/);
    expect(sql).toMatch(/create table if not exists \S+flag_overrides/);
    expect(sql).toContain("extensions.digest(flag || '.' || target, 'sha256')");
    expect(sql).toContain("flag_enabled");
    expect(sql).toContain("'{}'::text[]");
  });

  it("matches plans against tenant_entitlements() when entitlements is installed", () => {
    expect(sqlOf(["organizations", "entitlements", "flags"])).toContain(
      "tenant_plans := better_supabase.tenant_entitlements(tenant)",
    );
  });
});

const withContexts = (contexts: unknown): string =>
  renderBlocks(["flags"], { modules: { flags: { options: { contexts } } } })
    .filter((file) => file.module === "flags")
    .map((file) => file.contents)
    .join("\n");

describe("flags module custom contexts", () => {
  it("reads each declared context from its table, in declared order", () => {
    const sql = withContexts({
      brand: { table: "public.organizations", column: "brand_id" },
      region: { table: "tenant_regions", column: "region", tenant: "org_id" },
    });

    expect(sql).toContain(
      `(select t."brand_id"::text from "public"."organizations" t where t."id" = flag_evaluation.tenant limit 1)`,
    );
    expect(sql).toContain(`where t."org_id" = flag_evaluation.tenant`);
    expect(sql).toContain("array_position(array['brand', 'region']::text[]");
  });

  it("reads no tenant table without contexts", () => {
    expect(withContexts(undefined)).not.toContain(
      "context_values := context_values ||",
    );
  });

  it.each([
    ["a list", [], "must map a context name"],
    [
      "an uppercase name",
      { Brand: { table: "t", column: "c" } },
      "lowercase identifier",
    ],
    [
      "a string source",
      { brand: "organizations" },
      "must be { table, column, tenant? }",
    ],
    [
      "a three-part table",
      { brand: { table: "a.b.c", column: "c" } },
      '"table" or "schema.table"',
    ],
    [
      "a quoted column",
      { brand: { table: "t", column: 'c"; drop' } },
      "brand.column",
    ],
    [
      "a numeric tenant",
      { brand: { table: "t", column: "c", tenant: 1 } },
      "brand.tenant",
    ],
  ])("rejects %s", (_, contexts, message) => {
    expect(() => withContexts(contexts)).toThrow(message);
  });

  it("writes nothing in custom mode", () => {
    expect(
      renderBlocks(["flags"], { modules: { flags: { mode: "custom" } } })
        .filter((file) => file.module === "flags")
        .map((file) => file.contents)
        .join(""),
    ).not.toContain("create table");
  });
});
