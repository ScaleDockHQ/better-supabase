import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/registry.ts";

const sqlOf = (names: readonly string[]): string =>
  renderModules(names)
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
