import { describe, expect, it } from "vitest";

import {
  emitPermissionScopes,
  grantMatches,
  permissionCatalogKeys,
  permissionCatalogSql,
} from "../../../src/cli/gen/permission-catalog.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";

const config = (
  model: "catalog" | "roles",
  tables?: { readonly permissions: string },
) =>
  resolveConfig(
    {
      blocks: {
        memberships: {},
        permissions: { model, ...(tables === undefined ? {} : { tables }) },
        advisories: {},
        leave: {},
      },
    },
    "/project",
  );

describe("grantMatches", () => {
  it("matches a bare star, a prefix and an exact key", () => {
    expect(grantMatches("*", "leave.read")).toBe(true);
    expect(grantMatches("leave.*", "leave.read")).toBe(true);
    expect(grantMatches("leave.read", "leave.read")).toBe(true);
    expect(grantMatches("leave.read", "leave.manage")).toBe(false);
    expect(grantMatches("lea.*", "leave.read")).toBe(false);
  });
});

describe("permissionCatalogKeys", () => {
  it("holds the keys a block checks, with the default roles", () => {
    const keys = new Map(
      permissionCatalogKeys(config("catalog")).map((entry) => [
        entry.key,
        entry,
      ]),
    );

    expect(keys.get("advisories.publish")?.roles).toStrictEqual([
      "owner",
      "admin",
    ]);

    expect(keys.get("leave.request")?.roles).toContain("member");
    expect(keys.get("leave.manage")?.roles).not.toContain("member");
  });

  it("grants members the read keys an entity declares", () => {
    const keys = new Map(
      permissionCatalogKeys(config("catalog")).map((entry) => [
        entry.key,
        entry,
      ]),
    );

    expect(keys.get("advisories.read")?.roles).toContain("member");
  });
});

describe("permissionCatalogSql", () => {
  it("inserts the keys and grants without repeating rows", () => {
    const sql = permissionCatalogSql(config("catalog"));

    expect(sql).toContain("('advisories.publish')");
    expect(sql).toContain("('admin', 'advisories.publish')");
    expect(sql).toContain("on conflict do nothing");
    expect(sql).toContain("where not exists");
  });

  it("is the same text for the same blocks", () => {
    expect(permissionCatalogSql(config("catalog"))).toBe(
      permissionCatalogSql(config("catalog")),
    );
  });

  it("needs the catalog model", () => {
    expect(() => permissionCatalogSql(config("roles"))).toThrow(
      /model: "catalog"/,
    );
  });

  it("refuses adopted catalog tables", () => {
    expect(() =>
      permissionCatalogSql(config("catalog", { permissions: "public.perms" })),
    ).toThrow(/managed catalog tables/);
  });
});

describe("emitPermissionScopes", () => {
  it("writes API key scopes and OAuth scopes without manage keys", () => {
    const file = emitPermissionScopes(config("catalog"));

    expect(file.path).toMatch(/permission-scopes\.ts$/);
    expect(file.contents).toContain("export const apiKeyScopes");
    expect(file.contents).toContain('"leave.manage",');

    const oauth = file.contents.slice(
      file.contents.indexOf("export const oauthScopes"),
    );

    expect(oauth).toContain('"leave.read",');
    expect(oauth).not.toContain('"leave.manage",');
  });
});
