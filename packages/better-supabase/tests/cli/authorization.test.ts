import { describe, expect, it } from "vitest";

import {
  accessProviderMode,
  accessRequirements,
  entitlementRequirements,
  entitlementsMode,
  keyStatus,
  moduleKeyProblems,
  providerLabel,
  unsafeKey,
} from "../../src/cli/authorization.ts";
import { resolveConfig } from "../../src/config/index.ts";
import {
  stubProvider,
  withProvider,
} from "../fixtures/authorization-provider.ts";

const invalid = (problem: RegExp) => ({
  kind: "invalid",
  problem: expect.stringMatching(problem),
});

describe("providerLabel", () => {
  it("names the provider without assuming which one it is", () => {
    expect(providerLabel(stubProvider)).toBe(
      "the authorization provider (stub)",
    );
  });
});

describe("entitlementsMode", () => {
  it("defaults to the provider's member functions when authorization is set", () => {
    const config = resolveConfig({ authorization: stubProvider }, "/project");
    expect(config.entitlements.memberships).toBe("provider");
    expect(entitlementsMode(config)).toEqual({
      kind: "provider",
      provider: {
        name: "stub",
        scope: "organization",
        idType: "uuid",
        memberIds: stubProvider.functions.memberIds,
        memberIdsFor: stubProvider.functions.memberIdsFor,
        memberships: stubProvider.memberships,
      },
    });
  });

  it("keeps the tenant module without a provider or when asked", () => {
    expect(entitlementsMode(resolveConfig({}, "/project"))).toEqual({
      kind: "tenant",
    });
    expect(
      entitlementsMode(
        resolveConfig(
          {
            authorization: stubProvider,
            entitlements: { memberships: "tenant" },
          },
          "/project",
        ),
      ),
    ).toEqual({ kind: "tenant" });
  });

  it("only passes memberships that can hold the tenant scope", () => {
    const provider = withProvider({
      memberships: [
        ...stubProvider.memberships,
        {
          table: "authz.project_members",
          userColumn: "user_id",
          scope: { value: "project" },
          idColumn: "project_id",
        },
      ],
    });
    expect(
      entitlementsMode(resolveConfig({ authorization: provider }, "/project")),
    ).toMatchObject({
      provider: { memberships: stubProvider.memberships },
    });
  });

  it("refuses what the provider doesn't back instead of falling back", () => {
    expect(
      entitlementsMode(
        resolveConfig(
          { entitlements: { memberships: "provider" } },
          "/project",
        ),
      ),
    ).toEqual(invalid(/no authorization/));
    const { memberIdsFor: _, ...functions } = stubProvider.functions;
    expect(
      entitlementsMode(
        resolveConfig(
          { authorization: withProvider({ functions }) },
          "/project",
        ),
      ),
    ).toEqual(invalid(/no authorization\.functions\.memberIdsFor/));
    expect(
      entitlementsMode(
        resolveConfig(
          { authorization: withProvider({ tenantScope: "workspace" }) },
          "/project",
        ),
      ),
    ).toEqual(invalid(/tenantScope "workspace" is not a scope/));
    expect(
      entitlementsMode(
        resolveConfig(
          {
            authorization: withProvider({
              scopes: [{ name: "organization", idType: "numeric" }],
            }),
          },
          "/project",
        ),
      ),
    ).toEqual(invalid(/scope "organization" has idType "numeric"/));
    expect(
      entitlementsMode(
        resolveConfig(
          {
            authorization: withProvider({ scopes: [{ name: "organization" }] }),
          },
          "/project",
        ),
      ),
    ).toEqual(invalid(/no idType/));
  });
});

describe("accessProviderMode", () => {
  const config = (
    access: object = {},
    provider: ReturnType<typeof withProvider> | null = stubProvider,
  ) =>
    resolveConfig(
      {
        ...(provider ? { authorization: provider } : {}),
        sql: { modules: { access: { model: "provider", ...access } } },
      },
      "/project",
    );

  it("passes the tenant scope, its id type and the functions", () => {
    expect(accessProviderMode(config())).toEqual({
      kind: "provider",
      access: {
        name: "stub",
        scope: "organization",
        idType: "uuid",
        functions: stubProvider.functions,
      },
    });
  });

  it("passes on suspension rows and role sources", () => {
    const user = {
      table: "public.profiles",
      id: "id",
      disabledAt: "banned_at",
    };
    const roleSources = [
      {
        table: "authz.memberships",
        role: {
          column: "role_id",
          through: { table: "authz.roles", id: "id", column: "key" },
        },
      },
    ];
    expect(
      accessProviderMode(
        config({}, withProvider({ suspension: { user }, roleSources })),
      ),
    ).toMatchObject({
      access: { suspension: { user }, roleSources },
    });
    expect(
      accessProviderMode(config({}, withProvider({ roleSources: [] }))),
    ).not.toHaveProperty("access.roleSources");
  });

  it("is off for the other models", () => {
    expect(
      accessProviderMode(
        resolveConfig(
          {
            authorization: stubProvider,
            sql: { modules: { access: { model: "roles" } } },
          },
          "/project",
        ),
      ),
    ).toEqual({ kind: "off" });
  });

  it("refuses a missing provider and a conflicting id type", () => {
    expect(accessProviderMode(config({}, null))).toEqual(
      invalid(/model is "provider", but the config has no authorization/),
    );
    expect(accessProviderMode(config({ idType: "text" }))).toEqual(
      invalid(/idType is "text", but .* the type uuid/),
    );
    expect(accessProviderMode(config({ idType: "uuid" }))).toMatchObject({
      kind: "provider",
    });
  });
});

describe("keyStatus and unsafeKey", () => {
  it("trusts only keys marked sqlComplete: true", () => {
    expect(keyStatus(stubProvider, "documents.read")).toBe("complete");
    expect(keyStatus(stubProvider, "documents.own")).toBe("incomplete");
    expect(keyStatus(stubProvider, "billing.read")).toBe("missing");
    expect(
      keyStatus(
        withProvider({ permissions: [{ key: "documents.read" }] }),
        "documents.read",
      ),
    ).toBe("unknown");
    expect(
      keyStatus(withProvider({ permissions: undefined }), "documents.read"),
    ).toBe("unknown");
  });

  it("explains each unsafe status", () => {
    expect(unsafeKey(stubProvider, "documents.read")).toBeUndefined();
    expect(unsafeKey(stubProvider, "documents.own")).toMatchObject({
      status: "incomplete",
      reason: expect.stringContaining("sqlComplete: false"),
    });
    expect(unsafeKey(stubProvider, "billing.read")).toMatchObject({
      status: "missing",
      reason: "is not in authorization.permissions",
    });
    expect(
      unsafeKey(withProvider({ permissions: undefined }), "documents.read"),
    ).toMatchObject({
      status: "unknown",
      reason: expect.stringContaining("authorization.permissions is not set"),
    });
  });
});

describe("moduleKeyProblems", () => {
  const keys = [
    {
      module: "organizations",
      action: "update",
      key: "documents.write",
      scope: "tenant",
    },
    {
      module: "invitations",
      action: "invite",
      key: "documents.own",
      scope: "tenant",
    },
    {
      module: "support-sessions",
      action: "start",
      key: "support.start",
      scope: "platform",
    },
  ] as const;

  it("passes complete keys and names the function and setting for the rest", () => {
    expect(moduleKeyProblems(stubProvider, keys)).toEqual([
      {
        target: "sql.modules.invitations.permissions.invite",
        message: expect.stringMatching(
          /checks "documents\.own" \(invite\) with authorization\.functions\.idsWith.*sqlComplete: false/,
        ),
      },
      {
        target: "sql.modules.support-sessions.permissions.start",
        message: expect.stringMatching(
          /checks "support\.start" \(start\) with authorization\.functions\.isPlatform.*not in authorization\.permissions/,
        ),
      },
    ]);
  });

  it("refuses every key when the provider lists no permissions", () => {
    const provider = withProvider({ permissions: undefined });
    expect(moduleKeyProblems(provider, keys)).toEqual([
      {
        target: "authorization.permissions",
        message: expect.stringContaining("passes 3 module permission keys"),
      },
    ]);
    expect(moduleKeyProblems(provider, [])).toEqual([]);
  });
});

describe("requirements", () => {
  it("lists the functions the access model calls as authenticated", () => {
    const mode = accessProviderMode(
      resolveConfig(
        {
          authorization: stubProvider,
          sql: { modules: { access: { model: "provider" } } },
        },
        "/project",
      ),
    );
    if (mode.kind !== "provider") throw new Error("expected provider mode");
    expect(accessRequirements(mode.access)).toEqual([
      {
        function: "authz.ids_organization",
        template: "idsWith",
        role: "authenticated",
      },
      {
        function: "authz.is_platform",
        template: "isPlatform",
        role: "authenticated",
      },
    ]);
  });

  it("lists the entitlements module's callers and roles", () => {
    const mode = entitlementsMode(
      resolveConfig({ authorization: stubProvider }, "/project"),
    );
    if (mode.kind !== "provider") throw new Error("expected provider mode");
    expect(entitlementRequirements(mode.provider)).toEqual([
      {
        kind: "member",
        function: "authz.member_organization_ids",
        template: "memberIds",
        caller: "has_entitlement",
        role: "authenticated",
      },
      {
        kind: "member-for",
        function: "authz.member_organization_ids_for",
        template: "memberIdsFor",
        caller: "feature_claims",
        role: "supabase_auth_admin",
      },
    ]);
  });
});
