import { describe, expect, it } from "vitest";

import type { AuthorizationProvider } from "../../src/config/index.ts";

import {
  accessProviderMode,
  entitlementsMode,
  keyStatus,
} from "../../src/cli/authorization.ts";
import {
  permissionLevelKey,
  providerApiProblem,
  resolveConfig,
  resolvePersonas,
  splitPermissionLevel,
} from "../../src/config/index.ts";
import { providerPersonaTests } from "../../src/create/lite/matrix-tests.ts";
import { moduleBody } from "../../src/sql/render.ts";

/**
 * A provider that fills the 0.26 fields and leaves out `memberIds` and
 * `memberIdsFor`, `personas` and the subject templates a hand-written provider
 * would add.
 */
const provider: AuthorizationProvider = {
  apiVersion: 1,
  name: "row-contract",
  scopes: [{ name: "organization", idType: "uuid" }],
  tenantScope: "organization",
  functions: {
    idsWith: "authz.ids_{scope}({permission})",
    isPlatform: "authz.is_platform({permission})",
    subject: "authz.subject_for_caller",
    subjectForTenant: "authz.subject_for(auth.uid(), {tenant})",
    bootstrapPermissions: "authz.bootstrap_permissions({tenant})",
    approverFor: "authz.approver_for_ids()",
    managedUsers: "authz.managed_user_ids()",
  },
  permissions: [
    { key: "file.read", sqlComplete: true, levels: ["own", "team"] },
  ],
  memberships: [
    {
      table: "authz.members",
      userColumn: "user_id",
      userKey: "auth_user_id",
      scope: { value: "organization" },
      idColumn: "organization_id",
      disabledAt: "disabled_at",
    },
  ],
  suspension: {
    user: { table: "public.profiles", id: "user_id", disabledAt: "banned_at" },
    userKey: "user_id",
  },
  personas: "roles",
  fixtureRoles: [
    {
      name: "viewer",
      setup: "select 1 /* {user} {tenant} */;",
      permissions: ["file.read"],
    },
  ],
  tokenHook: {
    function: "authz.hook",
    ownedClaims: ["permissions"],
    teamIdsTruncatedClaim: "team_ids_truncated",
  },
};

describe("a provider that fills only the 0.26 fields", () => {
  it("stays on API version 1", () => {
    expect(providerApiProblem(provider)).toBeUndefined();
  });

  it("derives the entitlements member templates from the membership rows", () => {
    const config = resolveConfig({ auth: { authorization: provider } }, "/p");
    const mode = entitlementsMode(config);

    expect(mode).toMatchObject({
      kind: "provider",
      provider: {
        memberIds: expect.stringContaining(
          'from "authz"."members" m where m."auth_user_id" = (select auth.uid())',
        ),
        memberIdsFor: expect.stringContaining('m."auth_user_id" = {user}'),
      },
    });
    expect(JSON.stringify(mode)).toContain('m.\\"disabled_at\\" is null');
  });

  it("lets a template the provider sets win over the derived one", () => {
    const own = {
      ...provider,
      functions: { ...provider.functions, memberIds: "authz.mine()" },
    };

    const mode = entitlementsMode(
      resolveConfig({ auth: { authorization: own } }, "/p"),
    );

    expect(mode).toMatchObject({
      kind: "provider",
      provider: { memberIds: "authz.mine()" },
    });
  });

  it("still refuses a provider with neither the templates nor membership rows", () => {
    const bare = {
      ...provider,
      memberships: undefined,
    } as unknown as AuthorizationProvider;

    expect(
      entitlementsMode(resolveConfig({ auth: { authorization: bare } }, "/p")),
    ).toMatchObject({ kind: "invalid" });
  });

  it("hands the user key of the suspension to the access module", () => {
    const config = resolveConfig(
      {
        auth: { authorization: provider },
        blocks: { permissions: { model: "provider" } },
      },
      "/p",
    );

    const mode = accessProviderMode(config);

    expect(mode).toMatchObject({
      kind: "provider",
      access: { suspension: { userKey: "user_id" } },
    });
  });

  it("turns personas 'roles' into one persona per fixture role", () => {
    expect(resolvePersonas(provider)).toEqual([
      {
        name: "viewer",
        setup: "select 1 /* {user} {tenant} */;",
        permissions: ["file.read"],
      },
    ]);

    const files = providerPersonaTests(provider, {
      tenant: "00000000-0000-4000-8000-000000000001",
    });

    expect(files.map((file) => file.path)).toEqual([
      "supabase/tests/database/access_matrix_provider_viewer.test.sql",
    ]);
  });

  it("never calls a level key complete, and refuses a level the entry doesn't list", () => {
    expect(keyStatus(provider, "file.read")).toBe("complete");
    expect(keyStatus(provider, "file.read@team")).toBe("incomplete");
    expect(keyStatus(provider, "file.read@all")).toBe("missing");
    expect(keyStatus(provider, "other@team")).toBe("missing");
  });

  it("hands the hook's team claim to the hook plan", () => {
    const config = resolveConfig(
      {
        auth: { authorization: provider },
        blocks: { permissions: { model: "provider" } },
      },
      "/p",
    );

    const mode = accessProviderMode(config);

    expect(mode).toMatchObject({
      kind: "provider",
      access: { teamIdsTruncatedClaim: "team_ids_truncated" },
    });
  });

  it("writes level keys with @ and splits them back", () => {
    expect(permissionLevelKey("file.read", "team")).toBe("file.read@team");
    expect(permissionLevelKey("file.read", null)).toBe("file.read");
    expect(splitPermissionLevel("file.read@team")).toEqual({
      permission: "file.read",
      level: "team",
    });
    expect(splitPermissionLevel("file.read")).toEqual({
      permission: "file.read",
      level: null,
    });
    expect(splitPermissionLevel("file.read@")).toEqual({
      permission: "file.read@",
      level: null,
    });
  });

  it("asks for the subject of the named tenant in the bootstrap wrapper, and null when it is unknown", () => {
    const sql = moduleBody("sessions", {
      modules: {
        sessions: { options: { bootstrap: { home: "app.home_data" } } },
      },
      accessProvider: {
        name: "row-contract",
        scope: "organization",
        idType: "uuid",
        functions: provider.functions,
      },
    })!;

    expect(sql).toContain(
      "'subject', case when nullif(args ->> 'tenant', '') is null then to_jsonb(authz.subject_for_caller()) else to_jsonb(authz.subject_for(auth.uid(), (args ->> 'tenant'))) end",
    );
  });
});
