import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  accessPermdockMode,
  entitlementsMode,
  moduleKeyProblems,
  parseGrantsMarker,
  parseHookMarker,
  parseManifest,
  parseCatalog,
  readPermdock,
} from "../../src/cli/permdock.ts";
import { resolveConfig } from "../../src/config/index.ts";
import { permdockKeyStatus } from "../../src/sql/index.ts";
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

  it("reads rls.tenantClaim and refuses an unknown rls.mode", () => {
    expect(parseManifest(manifest).rls?.tenantClaim).toBe("tenant_id");
    expect(() =>
      parseManifest({ ...manifest, rls: { ...manifest.rls, mode: "edge" } }),
    ).toThrow(/rls\.mode "edge" is not supported/);
  });

  it("keeps each catalog key's rowConditions flag, and drops one that isn't boolean", () => {
    const catalog = parseCatalog({
      version: 1,
      permissions: [
        { key: "a", rowConditions: true, scope: "organization" },
        { key: "b", rowConditions: false },
        { key: "c" },
        { key: "d", rowConditions: "yes" },
        { rowConditions: false },
      ],
    });
    expect(catalog.permissions).toEqual([
      { key: "a", rowConditions: true, scope: "organization" },
      { key: "b", rowConditions: false },
      { key: "c" },
      { key: "d" },
    ]);
    expect(
      ["a", "b", "c", "d", "e"].map((key) => permdockKeyStatus(catalog, key)),
    ).toEqual([
      "row-conditions",
      "scope-only",
      "no-flag",
      "no-flag",
      "missing",
    ]);
    expect(() => parseCatalog({})).toThrow(/no permissions array/);
  });

  it("refuses a catalog that isn't version 1", () => {
    expect(() => parseCatalog({ version: 2, permissions: [] })).toThrow(
      /version 2 is not supported/,
    );
    expect(() => parseCatalog({ permissions: [] })).toThrow(
      /version undefined is not supported/,
    );
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
        idType: "uuid",
        memberships: [
          {
            table: "public.memberships",
            userColumn: "user_id",
            scope: { column: "scope" },
            idColumn: "scope_id",
          },
        ],
      },
    });
    expect(
      entitlementsMode(config({ permdock: { scope: "customer" } }), project),
    ).toMatchObject({
      kind: "permdock",
      permdock: {
        scope: "customer",
        memberships: [
          { table: "public.memberships" },
          { table: "public.contacts" },
        ],
      },
    });
  });

  it("reads memberships from rls.memberships, the tables PermDock's helpers read", () => {
    const helperTable = {
      table: "public.organization_members",
      user: { column: "member_id" },
      scope: { value: "organization" },
      id: { column: "org_id" },
      columns: ["member_id", "org_id"],
    };
    const differing = {
      ...project,
      manifest: parseManifest({
        ...manifest,
        rls: { ...manifest.rls, memberships: [helperTable] },
      }),
    };
    expect(entitlementsMode(config(), differing)).toMatchObject({
      kind: "permdock",
      permdock: {
        memberships: [
          {
            table: "public.organization_members",
            userColumn: "member_id",
            idColumn: "org_id",
          },
        ],
      },
    });
    const { memberships: _, ...olderRls } = manifest.rls;
    const older = {
      ...project,
      manifest: parseManifest({ ...manifest, rls: olderRls }),
    };
    expect(older.manifest.rls?.memberships).toBeUndefined();
    expect(entitlementsMode(config(), older)).toMatchObject({
      kind: "permdock",
      permdock: { memberships: [{ table: "public.memberships" }] },
    });
  });

  const withScopes = (
    scopes: readonly { name: string; type?: string; within?: string }[],
  ) => ({
    ...project,
    manifest: parseManifest({
      ...manifest,
      rls: { ...manifest.rls, scopes },
    }),
  });

  it("defaults the scope to the manifest's root scope", () => {
    expect(config().entitlements.permdock).toEqual({});
    const tenant = withScopes([
      { name: "tenant", type: "uuid" },
      { name: "team", type: "uuid", within: "tenant" },
    ]);
    expect(entitlementsMode(config(), tenant)).toMatchObject({
      kind: "permdock",
      permdock: { scope: "tenant" },
    });
    expect(entitlementsMode(config(), project)).toMatchObject({
      kind: "permdock",
      permdock: { scope: "organization" },
    });
  });

  it("keeps an explicit scope as the override", () => {
    const tenant = withScopes([
      { name: "tenant", type: "uuid" },
      { name: "team", type: "uuid", within: "tenant" },
    ]);
    expect(
      entitlementsMode(config({ permdock: { scope: "team" } }), tenant),
    ).toMatchObject({ kind: "permdock", permdock: { scope: "team" } });
    expect(
      entitlementsMode(config({ permdock: { scope: "organization" } }), tenant),
    ).toEqual({
      kind: "invalid",
      problem: expect.stringContaining(
        'entitlements.permdock.scope is "organization", but permdock.manifest.json has the scopes tenant, team',
      ),
    });
  });

  it("takes the scope's id type from the manifest", () => {
    for (const type of ["uuid", "text", "bigint", "integer"])
      expect(
        entitlementsMode(config(), withScopes([{ name: "tenant", type }])),
      ).toMatchObject({ kind: "permdock", permdock: { idType: type } });
  });

  it("normalises the case and aliases of the id type", () => {
    for (const [type, idType] of [
      ["UUID", "uuid"],
      ["int8", "bigint"],
      ["int4", "integer"],
      ["character  varying", "text"],
    ] as const)
      expect(
        entitlementsMode(config(), withScopes([{ name: "tenant", type }])),
      ).toMatchObject({ kind: "permdock", permdock: { idType } });
  });

  it("refuses a missing or unsupported scope id type instead of guessing uuid", () => {
    expect(
      entitlementsMode(config(), withScopes([{ name: "tenant" }])),
    ).toEqual({
      kind: "invalid",
      problem: expect.stringContaining(
        'permdock.manifest.json gives scope "tenant" no type',
      ),
    });
    expect(
      entitlementsMode(
        config(),
        withScopes([{ name: "tenant", type: "numeric" }]),
      ),
    ).toEqual({
      kind: "invalid",
      problem: expect.stringMatching(
        /scope "tenant" the type numeric.*uuid, text, bigint or integer/,
      ),
    });
  });

  it("asks for a scope when the manifest has no single root scope", () => {
    const twoRoots = withScopes([
      { name: "tenant", type: "uuid" },
      { name: "workspace", type: "uuid" },
    ]);
    expect(entitlementsMode(config(), twoRoots)).toEqual({
      kind: "invalid",
      problem: expect.stringMatching(
        /no single root scope \(tenant, workspace\).*entitlements\.permdock: \{ scope \}/,
      ),
    });
    expect(entitlementsMode(config(), withScopes([]))).toMatchObject({
      kind: "invalid",
    });
  });

  it("keeps the tenant module without PermDock or with permdock: false", () => {
    expect(entitlementsMode(config(), undefined)).toEqual({ kind: "tenant" });
    expect(entitlementsMode(config({ permdock: false }), project)).toEqual({
      kind: "tenant",
    });
  });

  it("refuses a PermDock project without a manifest or its rls block", () => {
    const { manifest: _, ...withoutManifest } = project;
    expect(
      entitlementsMode(config(), {
        ...withoutManifest,
        config: "permdock.config.ts",
      }),
    ).toEqual({
      kind: "invalid",
      problem: expect.stringMatching(
        /permdock\.config\.ts is a PermDock project, but there is no permdock\.manifest\.json.*permdock: false/,
      ),
    });
    expect(
      entitlementsMode(config(), {
        ...withoutManifest,
        problems: ["permdock.manifest.json: version 2 is not supported"],
      }),
    ).toEqual({
      kind: "invalid",
      problem: expect.stringContaining(
        "Could not read PermDock's manifest: permdock.manifest.json: version 2",
      ),
    });
    const { rls: _rls, ...withoutRls } = manifest;
    expect(
      entitlementsMode(config(), {
        ...project,
        manifest: parseManifest(withoutRls),
      }),
    ).toEqual({
      kind: "invalid",
      problem: expect.stringContaining("has no rls block"),
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

describe("accessPermdockMode", () => {
  const project = {
    manifestPath: "permdock.manifest.json",
    manifest: parseManifest(manifest),
    catalogPath: "permissions.catalog.json",
    problems: [],
  };
  const authz = {
    ...project,
    manifest: parseManifest({
      ...manifest,
      rls: {
        ...manifest.rls,
        schema: "authz",
        scopes: [
          { name: "tenant", type: "text" },
          { name: "team", type: "text", within: "tenant" },
        ],
      },
    }),
  };
  const config = (
    access: object = {},
    extra: Parameters<typeof resolveConfig>[0] = {},
  ) =>
    resolveConfig(
      {
        sql: { modules: { access: { model: "permdock", ...access } } },
        ...extra,
      },
      "/project",
    );

  it("reads the root scope, rls.schema and the scope's id type", () => {
    expect(accessPermdockMode(config(), authz)).toEqual({
      kind: "permdock",
      access: { schema: "authz", scope: "tenant", idType: "text" },
    });
    expect(
      accessPermdockMode(config({ permdock: { scope: "team" } }), authz),
    ).toMatchObject({ kind: "permdock", access: { scope: "team" } });
  });

  it("passes on membership roles PermDock reads through a roles table", () => {
    const team = {
      table: "public.team_members",
      user: { column: "user_id" },
      scope: { value: "tenant" },
      id: { column: "team_id" },
      role: {
        column: "role_id",
        through: { table: "public.team_roles", id: "id", column: "key" },
      },
      columns: ["user_id", "team_id", "role_id"],
    };
    const through = {
      ...authz,
      manifest: parseManifest({
        ...manifest,
        rls: {
          ...manifest.rls,
          schema: "authz",
          scopes: [{ name: "tenant", type: "text" }],
          memberships: [...manifest.rls.memberships, team],
        },
      }),
    };
    expect(through.manifest.rls?.memberships?.at(-1)?.role).toEqual(team.role);
    expect(accessPermdockMode(config(), through)).toMatchObject({
      kind: "permdock",
      access: {
        roleSources: [{ table: "public.team_members", role: team.role }],
      },
    });
  });

  it("lists PermDock's helpers for a named user the manifest advertises", () => {
    const helper = (name: string) => ({
      name,
      args: "p_user uuid, p_grant text",
      returns: "boolean",
      execute: [],
    });
    const withFor = {
      ...authz,
      manifest: parseManifest({
        ...manifest,
        rls: {
          ...manifest.rls,
          schema: "authz",
          scopes: [{ name: "tenant", type: "text" }],
          helpers: [
            ...manifest.rls.helpers,
            helper("permdock_has_for"),
            helper("permitted_tenant_ids_for"),
          ],
        },
      }),
    };
    expect(accessPermdockMode(config(), withFor)).toMatchObject({
      access: {
        forUser: { has: true, permitted: true, canAssign: false },
      },
    });
    expect(accessPermdockMode(config(), authz)).not.toHaveProperty(
      "access.forUser",
    );
  });

  it("doesn't depend on the entitlements setting", () => {
    expect(
      accessPermdockMode(
        config({}, { entitlements: { permdock: false } }),
        authz,
      ),
    ).toEqual(accessPermdockMode(config(), authz));
  });

  it("is off for the other models", () => {
    expect(
      accessPermdockMode(
        resolveConfig(
          { sql: { modules: { access: { model: "roles" } } } },
          "/project",
        ),
        authz,
      ),
    ).toEqual({ kind: "off" });
  });

  it("refuses what the manifest doesn't back", () => {
    const invalid = (problem: RegExp) => ({
      kind: "invalid",
      problem: expect.stringMatching(problem),
    });
    expect(accessPermdockMode(config(), undefined)).toEqual(
      invalid(/no PermDock project here/),
    );
    const { manifest: _, ...withoutManifest } = project;
    expect(
      accessPermdockMode(config(), {
        ...withoutManifest,
        config: "permdock.config.ts",
      }),
    ).toEqual(
      invalid(/there is no permdock\.manifest\.json.*modules\.access\.model/),
    );
    const { rls: _rls, ...withoutRls } = manifest;
    expect(
      accessPermdockMode(config(), {
        ...project,
        manifest: parseManifest(withoutRls),
      }),
    ).toEqual(invalid(/has no rls block, so the permdock access model/));
    const twoRoots = {
      ...project,
      manifest: parseManifest({
        ...manifest,
        rls: {
          ...manifest.rls,
          scopes: [
            { name: "tenant", type: "uuid" },
            { name: "workspace", type: "uuid" },
          ],
        },
      }),
    };
    expect(accessPermdockMode(config(), twoRoots)).toEqual(
      invalid(
        /no single root scope \(tenant, workspace\).*modules\.access\.permdock: \{ scope \}/,
      ),
    );
    expect(
      accessPermdockMode(
        config({ permdock: { scope: "organization" } }),
        authz,
      ),
    ).toEqual(
      invalid(
        /modules\.access\.permdock\.scope is "organization", but .* tenant, team/,
      ),
    );
    expect(
      accessPermdockMode(config({ permdock: { schema: "permdock" } }), authz),
    ).toEqual(
      invalid(
        /schema is "permdock", but .* puts PermDock's helpers in "authz"/,
      ),
    );
    expect(accessPermdockMode(config({ idType: "uuid" }), authz)).toEqual(
      invalid(/modules\.access\.idType is "uuid", but .* the type text/),
    );
    const untyped = {
      ...project,
      manifest: parseManifest({
        ...manifest,
        rls: { ...manifest.rls, scopes: [{ name: "tenant", type: "numeric" }] },
      }),
    };
    expect(accessPermdockMode(config(), untyped)).toEqual(
      invalid(/type numeric, but the permdock access model renders only/),
    );
  });
});

describe("moduleKeyProblems", () => {
  const access = { schema: "authz", scope: "tenant", idType: "uuid" } as const;
  const catalog = parseCatalog({
    version: 1,
    permissions: [
      { key: "organization.update", rowConditions: false },
      { key: "members.invite", rowConditions: true },
      { key: "support.start" },
    ],
  });
  const project = {
    manifestPath: "permdock.manifest.json",
    catalogPath: "permissions.catalog.json",
    catalog,
    problems: [],
  };
  const keys = [
    {
      module: "organizations",
      action: "update",
      key: "organization.update",
      scope: "tenant",
    },
    {
      module: "invitations",
      action: "invite",
      key: "members.invite",
      scope: "tenant",
    },
    {
      module: "support-sessions",
      action: "start",
      key: "support.start",
      scope: "platform",
    },
    {
      module: "notifications",
      action: "send",
      key: "notifications.send",
      scope: "tenant",
    },
  ] as const;

  it("passes scope-only keys and refuses the other statuses", () => {
    expect(moduleKeyProblems(project, keys, access)).toEqual([
      {
        target: "sql.modules.invitations.permissions.invite",
        message: expect.stringMatching(
          /checks "members\.invite" \(invite\) with authz\.permitted_tenant_ids, but it has row conditions.*rowConditions: false/,
        ),
      },
      {
        target: "sql.modules.support-sessions.permissions.start",
        message: expect.stringMatching(
          /checks "support\.start" \(start\) with authz\.permdock_has, but it has no rowConditions flag.*permdock catalog/,
        ),
      },
      {
        target: "sql.modules.notifications.permissions.send",
        message: expect.stringMatching(
          /"notifications\.send".*is not in permissions\.catalog\.json.*permdock catalog.*a key the catalog lists/,
        ),
      },
    ]);
  });

  it("refuses every key without a readable catalog", () => {
    const { catalog: _, ...withoutCatalog } = project;
    expect(moduleKeyProblems(withoutCatalog, keys, access)).toEqual([
      {
        target: "permissions.catalog.json",
        message: expect.stringContaining(
          "there is no permissions.catalog.json",
        ),
      },
    ]);
    expect(
      moduleKeyProblems(
        {
          ...withoutCatalog,
          problems: ["permissions.catalog.json: version 2 is not supported"],
        },
        keys,
        access,
      ),
    ).toEqual([
      {
        target: "permissions.catalog.json",
        message: expect.stringContaining("Could not read PermDock's catalog"),
      },
    ]);
    expect(moduleKeyProblems(withoutCatalog, [], access)).toEqual([]);
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
        version: 1,
        permissions: [{ key: "docs.read", rowConditions: true }],
      }),
    );
    const project = await readPermdock(root, PATHS);
    expect(project?.config).toBe("permdock.config.ts");
    expect(project?.manifest?.hook?.function).toBe("custom_access_token_hook");
    expect(project?.catalog).toEqual({
      permissions: [{ key: "docs.read", rowConditions: true }],
    });
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
