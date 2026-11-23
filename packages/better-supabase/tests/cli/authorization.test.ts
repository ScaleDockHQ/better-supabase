import { describe, expect, it } from "vitest";

import {
  accessProviderMode,
  accessRequirements,
  entitlementRequirements,
  entitlementsMode,
  keyStatus,
  catalogKeyProblems,
  claimMarkerOverrides,
  moduleKeyProblems,
  providerKeyUses,
  providerLabel,
  tagKeyProblem,
  unsafeKey,
  sqlCompleteKeys,
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
    const config = resolveConfig(
      { auth: { authorization: stubProvider } },
      "/project",
    );

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
            auth: {
              authorization: stubProvider,
              entitlements: { memberships: "tenant" },
            },
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
      entitlementsMode(
        resolveConfig({ auth: { authorization: provider } }, "/project"),
      ),
    ).toMatchObject({ provider: { memberships: stubProvider.memberships } });
  });

  it("refuses what the provider doesn't back instead of falling back", () => {
    expect(
      entitlementsMode(
        resolveConfig(
          { auth: { entitlements: { memberships: "provider" } } },
          "/project",
        ),
      ),
    ).toEqual(invalid(/no authorization/));
    const { memberIdsFor: _, ...functions } = stubProvider.functions;
    expect(
      entitlementsMode(
        resolveConfig(
          {
            auth: {
              authorization: withProvider({ functions, memberships: [] }),
            },
          },
          "/project",
        ),
      ),
    ).toEqual(invalid(/no authorization\.functions\.memberIdsFor/));
    expect(
      entitlementsMode(
        resolveConfig(
          {
            auth: { authorization: withProvider({ tenantScope: "workspace" }) },
          },
          "/project",
        ),
      ),
    ).toEqual(invalid(/tenantScope "workspace" is not a scope/));
    expect(
      entitlementsMode(
        resolveConfig(
          {
            auth: {
              authorization: withProvider({
                scopes: [{ name: "organization", idType: "numeric" }],
              }),
            },
          },
          "/project",
        ),
      ),
    ).toEqual(invalid(/scope "organization" has idType "numeric"/));
    expect(
      entitlementsMode(
        resolveConfig(
          {
            auth: {
              authorization: withProvider({
                scopes: [{ name: "organization" }],
              }),
            },
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
        blocks: { permissions: { model: "provider", ...access } },
      },
      "/project",
    );

  it("passes the tenant scope, every scope, its id type and the functions", () => {
    expect(accessProviderMode(config())).toEqual({
      kind: "provider",
      access: {
        name: "stub",
        scope: "organization",
        scopes: ["organization", "project"],
        idType: "uuid",
        functions: stubProvider.functions,
        memberships: stubProvider.memberships,
        sqlCompleteKeys: sqlCompleteKeys(stubProvider),
        tokenHook: { function: "authz.access_token_hook" },
        truncatedClaim: "memberships_truncated",
      },
    });
  });

  it("passes on the sqlComplete keys and whether the hook owns permissions", () => {
    const base = config();

    const owning = {
      ...base,
      authorization: {
        ...stubProvider,
        permissions: [
          { key: "projects.read", sqlComplete: true },
          { key: "projects.share" },
        ],
        tokenHook: {
          function: "authz.hook",
          ownedClaims: ["memberships", "permissions"],
          truncatedClaim: "perms_partial",
        },
      },
    };

    const mode = accessProviderMode(owning);

    expect(mode.kind === "provider" ? mode.access : undefined).toMatchObject({
      sqlCompleteKeys: ["projects.read"],
      ownsPermissions: true,
      truncatedClaim: "perms_partial",
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
    ).toMatchObject({ access: { suspension: { user }, roleSources } });
    expect(
      accessProviderMode(config({}, withProvider({ roleSources: [] }))),
    ).not.toHaveProperty("access.roleSources");
  });

  it("passes on tenant suspension, operations and wildcards", () => {
    const tenant = { table: "public.orgs", id: "id", disabledAt: "closed_at" };
    const operations = { search: { permission: "notes.read" } };

    const mode = accessProviderMode(
      config(
        {},
        withProvider({
          suspension: { tenant, userKey: "auth_id" },
          operations,
          wildcards: "prefix",
        }),
      ),
    );

    expect(mode.kind === "provider" ? mode.access : undefined).toMatchObject({
      suspension: { tenant, userKey: "auth_id" },
      operations,
      wildcards: "prefix",
    });
    expect(mode).not.toHaveProperty("access.suspension.user");
    expect(
      accessProviderMode(config({}, withProvider({ operations: {} }))),
    ).not.toHaveProperty("access.operations");
  });

  it("refuses a provider whose scopes are inconsistent", () => {
    expect(
      accessProviderMode(
        config({}, withProvider({ tenantScope: "workspace" })),
      ),
    ).toEqual(
      invalid(/are inconsistent: tenantScope "workspace" is not a scope/),
    );
  });

  it("passes on platform roles and memberships", () => {
    const platformRoles = {
      table: "app.platform_roles",
      user: "user_id",
      role: "role",
    };

    const memberships = [
      {
        table: "app.members",
        userColumn: "user_id",
        scope: { column: "org_id" },
        idColumn: "id",
        disabledAt: "disabled_at",
      },
    ];

    expect(
      accessProviderMode(
        config({}, withProvider({ platformRoles, memberships })),
      ),
    ).toMatchObject({ access: { platformRoles, memberships } });
    expect(
      accessProviderMode(config({}, withProvider({ memberships: [] }))),
    ).not.toHaveProperty("access.memberships");
  });

  it("is off for the other models", () => {
    expect(
      accessProviderMode(
        resolveConfig(
          {
            auth: { authorization: stubProvider },
            blocks: { permissions: { model: "roles" } },
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

describe("catalogKeyProblems", () => {
  it("checks operation and tag keys like module keys", () => {
    const problems = catalogKeyProblems(stubProvider, [
      {
        key: "documents.write",
        target: "authorization.operations.a.permission",
        checker: "The a operation",
      },
      {
        key: "documents.own",
        target: "the @bsb access tag",
        checker: "The @bsb access tag",
      },
    ]);

    expect(problems).toEqual([
      {
        target: "the @bsb access tag",
        message: expect.stringMatching(
          /The @bsb access tag checks "documents\.own".*sqlComplete: false/,
        ),
      },
    ]);
  });

  it("says nothing without a permissions list", () => {
    expect(
      catalogKeyProblems(withProvider({ permissions: undefined }), [
        { key: "x", target: "t", checker: "c" },
      ]),
    ).toEqual([]);
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
      module: "impersonation",
      action: "start",
      key: "impersonation.start",
      scope: "platform",
    },
  ] as const;

  it("passes complete keys and names the function and setting for the rest", () => {
    expect(moduleKeyProblems(stubProvider, keys)).toEqual([
      {
        target: "blocks.invitations.permissions.invite",
        message: expect.stringMatching(
          /checks "documents\.own" \(invite\) with authorization\.functions\.idsWith.*sqlComplete: false/,
        ),
      },
      {
        target: "blocks.impersonation.permissions.start",
        message: expect.stringMatching(
          /checks "impersonation\.start" \(start\) with authorization\.functions\.isPlatform.*not in authorization\.permissions/,
        ),
      },
    ]);
  });

  it("names an option that sets the key outside permissions", () => {
    expect(
      moduleKeyProblems(stubProvider, [
        {
          module: "numbering",
          action: "assign",
          key: "documents.own",
          scope: "tenant",
          setting:
            "blocks.number-sequences.options.entities.invoice.permission",
        },
      ]),
    ).toEqual([
      {
        target: "blocks.number-sequences.options.entities.invoice.permission",
        message: expect.stringContaining("documents.own"),
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
          auth: { authorization: stubProvider },
          blocks: { permissions: { model: "provider" } },
        },
        "/project",
      ),
    );

    if (mode.kind !== "provider") {
      throw new Error("expected provider mode");
    }

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
      resolveConfig({ auth: { authorization: stubProvider } }, "/project"),
    );

    if (mode.kind !== "provider") {
      throw new Error("expected provider mode");
    }

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

describe("derived member templates", () => {
  const {
    memberIds: _ids,
    memberIdsFor: _for,
    ...functions
  } = stubProvider.functions;

  const mode = (provider: object) =>
    entitlementsMode({
      entitlements: { memberships: "provider" },
      authorization: { ...stubProvider, functions, ...provider },
    } as unknown as Parameters<typeof entitlementsMode>[0]);

  it("reads memberIds off the membership rows of the tenant scope", () => {
    const result = mode({
      memberships: [
        {
          table: 'authz.team"s',
          userColumn: "profile_id",
          userKey: "user_id",
          scope: { value: "organization" },
          idColumn: "org_id",
          disabledAt: "disabled_at",
        },
        {
          table: "authz.other",
          userColumn: "u",
          scope: { value: "project" },
          idColumn: "p",
        },
        {
          table: "authz.memberships",
          userColumn: "user_id",
          scope: { column: "kind" },
          idColumn: "scope_id",
        },
      ],
    });

    expect(result).toMatchObject({
      kind: "provider",
      provider: {
        memberIds:
          '(select m."org_id" as id from "authz"."team""s" m where m."user_id" = (select auth.uid()) and m."disabled_at" is null union select m."scope_id" as id from "authz"."memberships" m where m."user_id" = (select auth.uid()) and m."kind" = \'{scope}\')',
        memberIdsFor: expect.stringContaining(
          'm."user_id" = {user} and m."disabled_at" is null',
        ),
      },
    });
  });

  it("keeps a template the provider sets over the derived one", () => {
    const result = mode({
      functions: { ...functions, memberIds: "authz.mine()" },
    });

    expect(result).toMatchObject({
      kind: "provider",
      provider: {
        memberIds: "authz.mine()",
        memberIdsFor: expect.stringContaining("{user}"),
      },
    });
  });

  it("is invalid without templates or memberships", () => {
    expect(mode({ memberships: [] })).toEqual(
      invalid(
        /no authorization\.functions\.memberIds and no authorization\.memberships/,
      ),
    );
    expect(
      mode({ memberships: [], functions: { ...functions, memberIds: "x()" } }),
    ).toEqual(invalid(/functions\.memberIdsFor/));
  });

  it("is invalid for a tenant scope without an id type or with one it can't render", () => {
    expect(mode({ scopes: [{ name: "organization" }] })).toEqual(
      invalid(/are inconsistent: tenant scope "organization" has no idType/),
    );
    expect(
      mode({ scopes: [{ name: "organization", idType: "jsonb" }] }),
    ).toEqual(invalid(/has idType "jsonb"; use uuid/));
  });
});

describe("tagKeyProblem", () => {
  const { permissions: _, ...unlisted } = stubProvider;

  it("is undefined without a provider permission list", () => {
    expect(tagKeyProblem(undefined)).toBeUndefined();
    expect(tagKeyProblem(unlisted)).toBeUndefined();
  });

  it("explains a key the provider does not list", () => {
    const check = tagKeyProblem({
      ...stubProvider,
      permissions: [{ key: "notes.read", sqlComplete: true }],
    });

    expect(check?.("notes.read")).toBeUndefined();
    expect(check?.("notes.write")).toMatch(
      /^The @bsb access tag checks "notes\.write" .+ is not in authorization\.permissions/,
    );
  });
});

describe("providerKeyUses", () => {
  it("lists operation, bucket and topic keys with their settings", () => {
    expect(
      providerKeyUses({
        ...stubProvider,
        operations: { search: { permission: "notes.read" } },
        actionKeys: {
          buckets: { avatars: { upload: "files.write" } },
          topics: { chat: { read: "chat.read" } },
        },
      }),
    ).toEqual([
      {
        key: "notes.read",
        target: "authorization.operations.search.permission",
        checker: "The search operation",
      },
      {
        key: "files.write",
        target: "authorization.actionKeys.buckets.avatars.upload",
        checker: "The avatars bucket (upload)",
      },
      {
        key: "chat.read",
        target: "authorization.actionKeys.topics.chat.read",
        checker: "The chat topic (read)",
      },
    ]);
  });

  it("is empty for a provider without operations or action keys", () => {
    expect(providerKeyUses(stubProvider)).toEqual([]);
  });
});

describe("claimMarkerOverrides", () => {
  const overrides = (authorization: object | undefined, hook?: unknown) =>
    claimMarkerOverrides({
      authorization,
      blocks: hook === undefined ? {} : { sessions: { options: { hook } } },
    } as unknown as Parameters<typeof claimMarkerOverrides>[0]);

  it("records markers that differ from the defaults", () => {
    expect(
      overrides({
        tokenHook: {
          ownedClaims: [],
          budget: { truncatedClaim: "perm_cut" },
          teamIdsTruncatedClaim: "teams_cut",
        },
      }),
    ).toEqual({
      permissionsTruncated: "perm_cut",
      teamIdsTruncated: "teams_cut",
    });
  });

  it("lets the sessions hook option win and drops the default team marker", () => {
    expect(overrides(undefined, { teamIdsTruncatedClaim: "hook_cut" })).toEqual(
      { teamIdsTruncated: "hook_cut" },
    );
    expect(
      overrides(undefined, { teamIdsTruncatedClaim: "team_ids_truncated" }),
    ).toEqual({});
    expect(overrides(undefined, "not a record")).toEqual({});
  });
});
