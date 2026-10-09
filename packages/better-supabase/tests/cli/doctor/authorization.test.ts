import { describe, expect, it } from "vitest";

import type {
  Catalog,
  CatalogFunction,
  Snapshot,
} from "../../../src/cli/introspect/types.ts";
import type {
  AuthorizationProvider,
  BetterSupabaseConfig,
} from "../../../src/config/index.ts";
import type { AccessBucketPolicy } from "../../../src/schema/types.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { providerBucketKeys } from "../../../src/cli/doctor/authorization.ts";
import {
  type DoctorContext,
  RULES,
  runRules,
} from "../../../src/cli/doctor/rules.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import {
  stubProvider,
  withProvider,
} from "../../fixtures/authorization-provider.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const base = await parseSnapshot(fixture);

/** The fixture with schema `authz` read and `names` defined in it. */
function withAuthz(names: readonly string[]): Snapshot {
  const copy = structuredClone(toCatalog(base)) as {
    -readonly [K in keyof Catalog]: Catalog[K];
  };
  copy.schemas = [...copy.schemas, "authz"];
  const functions = copy.functions as CatalogFunction[];
  for (const name of names)
    functions.push({ ...functions[0]!, schema: "authz", name });
  return fromCatalog(copy);
}

const SQL = {
  idsWith: stubProvider.functions.idsWith,
  isPlatform: stubProvider.functions.isPlatform,
};

const ALL = stubProvider.requires.map((entry) =>
  entry.function.slice("authz.".length),
);

function context(
  config: Parameters<typeof resolveConfig>[0],
  extra: Partial<DoctorContext> = {},
): DoctorContext {
  return {
    config: resolveConfig(config, "/project"),
    snapshot: base,
    configToml: undefined,
    envFiles: [],
    gitignore: "",
    sources: [],
    ...extra,
  };
}

const rule = (code: string) => RULES.filter((entry) => entry.code === code);

const findings = async (
  code: string,
  config: Parameters<typeof resolveConfig>[0],
  extra: Partial<DoctorContext> = {},
) =>
  (await runRules(context(config, extra), rule(code))).map((finding) => ({
    severity: finding.severity,
    target: finding.target,
    message: finding.message,
  }));

describe("providerBucketKeys", () => {
  it("reads buckets with sql templates, or every access bucket under the provider model", () => {
    const buckets = {
      docs: {
        path: "{organizationId}/{...rest}",
        policy: {
          access: { read: "documents.read", write: "documents.write" },
          sql: SQL,
        },
      },
      avatars: {
        path: "{organizationId}/{...rest}",
        policy: {
          access: { read: "documents.read", write: "documents.write" },
        },
      },
      public: { path: "{...rest}", policy: "public" },
    } as const;
    const config = (model?: "provider") =>
      resolveConfig(
        {
          authorization: stubProvider,
          buckets,
          ...(model ? { sql: { modules: { access: { model } } } } : {}),
        },
        "/project",
      );
    expect(providerBucketKeys(config())).toEqual([
      {
        bucket: "docs",
        keys: ["documents.read", "documents.write"],
        scope: "organization",
      },
    ]);
    expect(
      providerBucketKeys(config("provider")).map((entry) => entry.bucket),
    ).toEqual(["docs", "avatars"]);
    expect(providerBucketKeys(resolveConfig({ buckets }, "/project"))).toEqual(
      [],
    );
  });
});

describe("BS214", () => {
  const bucket = (
    access: AccessBucketPolicy["access"],
    scope?: string,
    provider: AuthorizationProvider = stubProvider,
  ) => ({
    authorization: provider,
    buckets: {
      docs: {
        path: "{organizationId}/{...rest}",
        policy: { access, sql: SQL, ...(scope ? { scope } : {}) },
      },
    },
  });

  it("passes complete keys at their scopes", async () => {
    expect(
      await findings(
        "BS214",
        bucket({ read: "documents.read", write: "documents.read" }, "project"),
      ),
    ).toEqual([]);
    expect(await findings("BS214", {})).toEqual([]);
  });

  it("warns when a bucket's copied templates drift from the provider", async () => {
    const keys = { read: "documents.read", write: "documents.read" };
    const policy = (sql: NonNullable<AccessBucketPolicy["sql"]>) => ({
      authorization: stubProvider,
      buckets: {
        docs: {
          path: "{organizationId}/{...rest}",
          policy: { access: keys, sql },
        },
      },
    });
    expect(
      await findings(
        "BS214",
        policy({
          ...SQL,
          idsWith: "authz.old_ids_with({permission}, {scope})",
        }),
      ),
    ).toEqual([
      {
        severity: "warning",
        target: "buckets.docs.policy.sql",
        message: expect.stringContaining(
          "copies sql templates that differ from the authorization provider (stub)'s idsWith",
        ),
      },
    ]);
    expect(await findings("BS214", policy("provider"))).toEqual([]);
  });

  it("flags incomplete, missing and unknown keys in buckets", async () => {
    expect(
      await findings(
        "BS214",
        bucket({ read: "documents.own", write: "billing.write" }),
      ),
    ).toEqual([
      {
        severity: "error",
        target: "buckets.docs:documents.own",
        message: expect.stringMatching(
          /buckets\.docs uses "documents\.own", which has conditions .*sqlComplete: false/,
        ),
      },
      {
        severity: "error",
        target: "buckets.docs:billing.write",
        message: expect.stringContaining("is not in authorization.permissions"),
      },
    ]);
    expect(
      await findings(
        "BS214",
        bucket(
          { read: "documents.read", write: "documents.read" },
          undefined,
          withProvider({ permissions: undefined }),
        ),
      ),
    ).toMatchObject([
      {
        message: expect.stringContaining(
          "authorization.permissions is not set",
        ),
      },
    ]);
  });

  it("flags undeclared scopes and keys checked at another scope", async () => {
    expect(
      await findings(
        "BS214",
        bucket(
          { read: "documents.read", write: "documents.read" },
          "workspace",
        ),
      ),
    ).toMatchObject([
      {
        message: expect.stringContaining(
          'uses scope "workspace", which the authorization provider (stub) doesn\'t declare',
        ),
      },
    ]);
    expect(
      await findings(
        "BS214",
        bucket({ read: "documents.read", write: "documents.write" }, "project"),
      ),
    ).toMatchObject([
      {
        message: expect.stringContaining(
          'checks "documents.write" at scope "project", but the authorization provider (stub) grants it at "organization"',
        ),
      },
    ]);
  });

  it("reads the keys generated bs_ policies pass to the provider's functions", async () => {
    const sqlFiles = [
      {
        path: "supabase/schemas/900_policies.sql",
        text: [
          `create policy "bs_docs_read" on "storage"."objects" for select using (bucket_id = 'docs' and (storage.foldername(name))[1] in (select t.id::text from authz.ids_organization('documents.own') as t(id)));`,
          `create policy bs_topic on realtime.messages for select using (authz.is_platform('platform.admin') or authz.ids_project( 'documents.write' ) is not null);`,
          `create policy "app_docs" on "storage"."objects" for select using (authz.ids_organization('billing.read') is not null);`,
        ].join("\n"),
      },
    ];
    expect(
      await findings("BS214", { authorization: stubProvider }, { sqlFiles }),
    ).toEqual([
      {
        severity: "error",
        target: "storage.objects.bs_docs_read:documents.own",
        message: expect.stringContaining(
          'Policy "bs_docs_read" on storage.objects passes "documents.own"',
        ),
      },
      {
        severity: "error",
        target: "realtime.messages.bs_topic:documents.write",
        message: expect.stringContaining('at scope "project"'),
      },
    ]);
  });
});

describe("BS408", () => {
  const config = (
    provider: AuthorizationProvider = stubProvider,
    extra: Parameters<typeof resolveConfig>[0] = {},
  ) => ({
    authorization: provider,
    sql: { modules: ["entitlements"] },
    ...extra,
  });

  it("passes when the provider and the database back the module", async () => {
    expect(
      await findings("BS408", config(), { snapshot: withAuthz(ALL) }),
    ).toEqual([]);
    expect(await findings("BS408", { authorization: stubProvider })).toEqual(
      [],
    );
    expect(
      await findings(
        "BS408",
        config(stubProvider, { entitlements: { memberships: "tenant" } }),
      ),
    ).toEqual([]);
  });

  it("reports a mode the provider can't back", async () => {
    const { memberIds: _, ...functions } = stubProvider.functions;
    expect(
      await findings("BS408", config(withProvider({ functions }))),
    ).toEqual([
      {
        severity: "warning",
        target: "entitlements.memberships",
        message: expect.stringContaining(
          "no authorization.functions.memberIds",
        ),
      },
    ]);
  });

  it("checks the features claim the provider's hook registers", async () => {
    const hook = (
      registeredClaims: { name: string; function: string }[],
    ): AuthorizationProvider =>
      withProvider({
        tokenHook: { ...stubProvider.tokenHook, registeredClaims },
      });
    const snapshot = withAuthz(ALL);
    expect(
      await findings(
        "BS408",
        config(hook([{ name: "features", function: "public.feature_claims" }])),
        { snapshot },
      ),
    ).toMatchObject([
      {
        target: "claims.features",
        message: expect.stringContaining(
          'fills the "features" claim from public.feature_claims, not better_supabase.feature_claims',
        ),
      },
    ]);
    expect(
      await findings(
        "BS408",
        config(
          hook([{ name: "plan", function: "better_supabase.feature_claims" }]),
        ),
        { snapshot },
      ),
    ).toMatchObject([
      { message: expect.stringContaining('Set claims.features to "plan"') },
    ]);
    expect(
      await findings("BS408", config(hook([])), { snapshot }),
    ).toMatchObject([
      { message: expect.stringContaining("entitlements.claim: false") },
    ]);
    expect(
      await findings(
        "BS408",
        config(hook([]), { entitlements: { claim: false } }),
        { snapshot },
      ),
    ).toEqual([]);
  });

  it("reports memberships that don't cover the tenant scope", async () => {
    const snapshot = withAuthz(ALL);
    expect(
      await findings(
        "BS408",
        config(withProvider({ memberships: undefined })),
        { snapshot },
      ),
    ).toMatchObject([
      { severity: "info", target: "authorization.memberships" },
    ]);
    expect(
      await findings(
        "BS408",
        config(
          withProvider({
            memberships: [
              {
                table: "authz.project_members",
                userColumn: "user_id",
                scope: { value: "project" },
                idColumn: "project_id",
              },
            ],
          }),
        ),
        { snapshot },
      ),
    ).toMatchObject([
      {
        severity: "warning",
        message: expect.stringContaining(
          'maps no membership table to scope "organization"',
        ),
      },
    ]);
  });

  it("reports functions requires doesn't list, a role it doesn't allow, or the database lacks", async () => {
    expect(
      await findings("BS408", config(), {
        snapshot: withAuthz(
          ALL.filter((name) => name !== "member_organization_ids"),
        ),
      }),
    ).toEqual([
      {
        severity: "warning",
        target: "authz.member_organization_ids",
        message: expect.stringContaining(
          "authz.member_organization_ids is not in the database, but has_entitlement calls it",
        ),
      },
    ]);
    expect(
      await findings(
        "BS408",
        config(
          withProvider({
            requires: stubProvider.requires.filter(
              (entry) => entry.function !== "authz.member_organization_ids",
            ),
          }),
        ),
        { snapshot: withAuthz(ALL) },
      ),
    ).toMatchObject([
      {
        message: expect.stringContaining(
          "doesn't list it in authorization.requires",
        ),
      },
    ]);
    expect(
      await findings(
        "BS408",
        config(
          withProvider({
            requires: stubProvider.requires.map((entry) =>
              entry.function === "authz.member_organization_ids_for"
                ? { ...entry, role: "authenticated" }
                : entry,
            ),
          }),
        ),
        { snapshot: withAuthz(ALL) },
      ),
    ).toEqual([
      {
        severity: "info",
        target: "authz.member_organization_ids_for",
        message: expect.stringContaining(
          "feature_claims calls it as supabase_auth_admin",
        ),
      },
    ]);
  });
});

describe("BS409", () => {
  it("passes when the claims match the provider", async () => {
    expect(
      await findings("BS409", {
        authorization: stubProvider,
        claims: { tenant: "tenant_id" },
      }),
    ).toEqual([]);
    expect(await findings("BS409", {})).toEqual([]);
  });

  it("reports the provider's problems, the tenant claim and claims.scope", async () => {
    expect(
      await findings("BS409", {
        authorization: withProvider({
          problems: ["the permission catalog is version 2"],
          tokenHook: { ...stubProvider.tokenHook, tenantClaim: "org_id" },
        }),
        claims: { scope: "workspace" },
      }),
    ).toEqual([
      {
        severity: "warning",
        target: "authorization",
        message:
          "the authorization provider (stub): the permission catalog is version 2",
      },
      {
        severity: "warning",
        target: "claims.tenant",
        message: expect.stringContaining(
          'writes the active tenant to "org_id", but claims.tenant is "tenant_id"',
        ),
      },
      {
        severity: "info",
        target: "claims.scope",
        message: expect.stringContaining(
          'the tenant scope of the authorization provider (stub) is "organization"',
        ),
      },
    ]);
  });

  it("notes suspension and role sources the access model ignores", async () => {
    const provider = withProvider({
      suspension: {
        user: { table: "authz.users", id: "id", disabledAt: "disabled_at" },
      },
    });
    expect(
      await findings("BS409", {
        authorization: provider,
        sql: { modules: { access: { model: "roles" } } },
      }),
    ).toEqual([
      {
        severity: "info",
        target: "authorization.suspension",
        message: expect.stringContaining(
          'sets suspension, but sql.modules.access.model is "roles"',
        ),
      },
    ]);
    expect(
      await findings("BS409", {
        authorization: provider,
        sql: { modules: { access: { model: "provider" } } },
      }),
    ).toEqual([]);
  });
});

describe("BS411", () => {
  const config = (
    provider: AuthorizationProvider | null = stubProvider,
    modules: Record<string, object> = {},
  ): BetterSupabaseConfig => ({
    ...(provider ? { authorization: provider } : {}),
    sql: { modules: { access: { model: "provider" }, ...modules } },
  });
  const snapshot = withAuthz(ALL);

  it("passes when the provider and the database back the model", async () => {
    expect(await findings("BS411", config(), { snapshot })).toEqual([]);
    expect(
      await findings("BS411", {
        authorization: stubProvider,
        sql: { modules: { access: { model: "roles" } } },
      }),
    ).toEqual([]);
  });

  it("reports a config the model can't use", async () => {
    expect(await findings("BS411", config(null))).toEqual([
      {
        severity: "error",
        target: "authorization",
        message: expect.stringContaining("has no authorization"),
      },
    ]);
  });

  it("reports functions the database lacks", async () => {
    expect(
      await findings("BS411", config(), {
        snapshot: withAuthz(ALL.filter((name) => name !== "is_platform")),
      }),
    ).toMatchObject([
      {
        target: "authz.is_platform",
        message: expect.stringContaining(
          "the provider access model (can() and the SQL modules) calls it",
        ),
      },
    ]);
  });

  it("reports module permission keys the provider doesn't mark complete", async () => {
    expect(
      await findings(
        "BS411",
        config(stubProvider, {
          invitations: { permissions: { invite: "documents.own" } },
        }),
        { snapshot },
      ),
    ).toContainEqual({
      severity: "error",
      target: "sql.modules.invitations.permissions.invite",
      message: expect.stringContaining('checks "documents.own" (invite)'),
    });
  });

  it("warns without canAssign, even with the tenant module", async () => {
    const { canAssign: _, ...functions } = stubProvider.functions;
    const noAssign = withProvider({ functions });
    expect(
      await findings("BS411", config(noAssign), { snapshot }),
    ).toMatchObject([
      {
        severity: "warning",
        target: "sql.modules.access.functions.canAssign",
      },
    ]);
    expect(
      await findings(
        "BS411",
        config(noAssign, {
          access: {
            model: "provider",
            functions: { canAssign: "authz.can_assign({tenant}, {role})" },
          },
        }),
        { snapshot },
      ),
    ).toEqual([]);
    expect(
      await findings("BS411", config(noAssign, { tenant: {} }), { snapshot }),
    ).toContainEqual(
      expect.objectContaining({
        target: "sql.modules.access.functions.canAssign",
        message: expect.stringContaining("only the service role assigns roles"),
      }),
    );
  });

  it("warns when an installed module calls a template the provider lacks", async () => {
    const {
      idsWithFor: _,
      canAssignFor: __,
      ...functions
    } = stubProvider.functions;
    const partial = withProvider({ functions });
    const result = await findings(
      "BS411",
      config(partial, { invitations: {}, comments: {} }),
      { snapshot },
    );
    expect(result).toContainEqual({
      severity: "warning",
      target: "authorization.functions.idsWithFor",
      message: expect.stringMatching(
        /The invitations, comments modules call authorization\.functions\.idsWithFor, which the authorization provider \(stub\) doesn't set/,
      ),
    });
    expect(result).toContainEqual({
      severity: "warning",
      target: "authorization.functions.canAssignFor",
      message: expect.stringContaining("can_assign_as is not written"),
    });
    expect(
      (
        await findings(
          "BS411",
          config(partial, {
            invitations: {},
            access: {
              model: "provider",
              functions: {
                canAssignFor: "authz.can_assign_for({user}, {tenant}, {role})",
              },
            },
          }),
          { snapshot },
        )
      ).map((finding) => finding.target),
    ).not.toContain("authorization.functions.canAssignFor");
    expect(
      (
        await findings("BS411", config(stubProvider, { invitations: {} }), {
          snapshot,
        })
      ).filter((finding) =>
        finding.target?.startsWith("authorization.functions"),
      ),
    ).toEqual([]);
  });
});
