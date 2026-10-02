import { resolveConfig } from "better-supabase/config";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  entitlementsMode,
  parseGrantsMarker,
  parseHookMarker,
  parseManifest,
  readPermdock,
  rowConditionKeys,
} from "../src/permdock.ts";
// Copied from PermDock's apps/examples/next-better-supabase/permdock.manifest.json.
import manifest from "./fixtures/permdock.manifest.json" with { type: "json" };

const PATHS = {
  manifest: "permdock.manifest.json",
  catalog: "permissions.catalog.json",
};

describe("PermDock manifest", () => {
  it("reads the hook, claims, sources, helpers and deciding columns", () => {
    const parsed = parseManifest(manifest);
    expect(parsed.hook).toEqual({
      schema: "public",
      function: "custom_access_token_hook",
    });
    expect(parsed.budget).toBe(1024);
    expect(
      parsed.claims.filter((claim) => claim.source !== "permdock"),
    ).toEqual([
      {
        name: "datetime_preferences",
        source: "public.datetime_preference_claims",
      },
      { name: "features", source: "public.feature_claims" },
    ]);
    expect(parsed.memberships[1]).toMatchObject({
      table: "public.contacts",
      user: { column: "user_id" },
      scope: { value: "customer" },
      id: { column: "customer_id" },
      role: { value: ["contact"] },
    });
    expect(parsed.rls?.helpers.map((helper) => helper.name)).toContain(
      "member_organization_ids_for",
    );
    expect(parsed.decidingColumns).toContain("public.contacts.user_id");
  });

  it("refuses other versions", () => {
    expect(() => parseManifest({ ...manifest, version: 2 })).toThrow(
      /version 2 is not supported/,
    );
    expect(() => parseManifest([])).toThrow(/not a JSON object/);
  });

  it("collects keys with row conditions from the catalog", () => {
    expect([
      ...rowConditionKeys({
        permissions: [
          { key: "a", rowConditions: true },
          { key: "b", rowConditions: false },
          { key: "c" },
        ],
      }),
    ]).toEqual(["a"]);
    expect(() => rowConditionKeys({})).toThrow(/no permissions array/);
  });

  it("parses the hook and grants markers", () => {
    expect(
      parseHookMarker(
        "-- permdock:hook v1 schema=public tenant=tenant_id budget=1024 claims=user_role,roles,features\ncreate function ...",
      ),
    ).toEqual({
      version: 1,
      schema: "public",
      tenantClaim: "tenant_id",
      budget: 1024,
      claims: ["user_role", "roles", "features"],
    });
    expect(parseGrantsMarker("-- permdock:grants v1 schema=public\n")).toEqual({
      version: 1,
      schema: "public",
    });
    expect(parseHookMarker("select 1")).toBeUndefined();
  });
});

describe("entitlementsMode", () => {
  const project = {
    manifestPath: "permdock.manifest.json",
    manifest: parseManifest(manifest),
    catalogPath: "permissions.catalog.json",
    problems: [],
  };
  const config = (entitlements = {}) =>
    resolveConfig({ entitlements }, "/project");

  it("uses PermDock's schema, scope and membership sources", () => {
    expect(entitlementsMode(config(), project)).toEqual({
      kind: "permdock",
      permdock: {
        schema: "public",
        scope: "organization",
        memberships: [
          {
            table: "public.memberships",
            userColumn: "user_id",
            scope: { column: "scope" },
            idColumn: "scope_id",
          },
          {
            table: "public.contacts",
            userColumn: "user_id",
            scope: { value: "customer" },
            idColumn: "customer_id",
          },
        ],
      },
    });
    expect(
      entitlementsMode(config({ permdock: { scope: "customer" } }), project),
    ).toMatchObject({ kind: "permdock", permdock: { scope: "customer" } });
  });

  it("keeps the tenant module without a manifest or with permdock: false", () => {
    const { manifest: _, ...withoutManifest } = project;
    expect(entitlementsMode(config(), undefined)).toEqual({ kind: "tenant" });
    expect(entitlementsMode(config(), withoutManifest)).toEqual({
      kind: "tenant",
    });
    expect(entitlementsMode(config({ permdock: false }), project)).toEqual({
      kind: "tenant",
    });
  });

  it("rejects a scope the manifest doesn't have", () => {
    expect(
      entitlementsMode(config({ permdock: { scope: "team" } }), project),
    ).toMatchObject({
      kind: "invalid",
      problem: expect.stringContaining('"team"'),
    });
  });
});

describe("readPermdock", () => {
  let root: string;
  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bs-permdock-"));
  });
  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  it("is undefined without a PermDock config or manifest", async () => {
    expect(await readPermdock(root, PATHS)).toBeUndefined();
  });

  it("reads the manifest and catalog next to the config", async () => {
    await writeFile(join(root, "permdock.config.ts"), "export default {}");
    await writeFile(join(root, PATHS.manifest), JSON.stringify(manifest));
    await writeFile(
      join(root, PATHS.catalog),
      JSON.stringify({
        permissions: [{ key: "docs.read", rowConditions: true }],
      }),
    );
    const project = await readPermdock(root, PATHS);
    expect(project?.config).toBe("permdock.config.ts");
    expect(project?.manifest?.hook?.function).toBe("custom_access_token_hook");
    expect([...(project?.rowConditions ?? [])]).toEqual(["docs.read"]);
    expect(project?.problems).toEqual([]);
  });

  it("reports unreadable files instead of throwing", async () => {
    await writeFile(join(root, PATHS.manifest), "{");
    await writeFile(join(root, PATHS.catalog), "[]");
    const project = await readPermdock(root, PATHS);
    expect(project?.manifest).toBeUndefined();
    expect(project?.problems).toEqual([
      expect.stringMatching(/^permdock\.manifest\.json: /),
      "permissions.catalog.json: has no permissions array",
    ]);
  });
});
