import type { AuthorizationProvider } from "../../src/config/index.ts";
import type { ModuleAccessProvider } from "../../src/sql/registry.ts";

type StubProvider = AuthorizationProvider & {
  readonly functions: Required<AuthorizationProvider["functions"]>;
  readonly memberships: NonNullable<AuthorizationProvider["memberships"]>;
  readonly requires: NonNullable<AuthorizationProvider["requires"]>;
  readonly tokenHook: NonNullable<AuthorizationProvider["tokenHook"]>;
};

/**
 * A neutral provider in schema `authz`: what an authorization system's
 * adapter would hand better-supabase. Organizations contain projects.
 */
export const stubProvider: StubProvider = {
  apiVersion: 1,
  name: "stub",
  scopes: [
    { name: "organization", idType: "uuid" },
    { name: "project", idType: "uuid", parent: "organization" },
  ],
  tenantScope: "organization",
  functions: {
    idsWith: "authz.ids_{scope}({permission})",
    isPlatform: "authz.is_platform({permission})",
    idsWithFor: "authz.ids_{scope}_for({user}, {permission})",
    isPlatformFor: "authz.is_platform_for({user}, {permission})",
    memberIds: "authz.member_{scope}_ids()",
    memberIdsFor: "authz.member_{scope}_ids_for({user})",
    canAssign: "authz.can_assign({tenant}, {role})",
    canAssignFor: "authz.can_assign_for({user}, {tenant}, {role})",
  },
  requires: [
    { function: "authz.ids_organization", args: "text", role: "authenticated" },
    { function: "authz.ids_project", args: "text", role: "authenticated" },
    { function: "authz.is_platform", args: "text", role: "authenticated" },
    {
      function: "authz.ids_organization_for",
      args: "uuid, text",
      role: "authenticated",
    },
    {
      function: "authz.ids_project_for",
      args: "uuid, text",
      role: "authenticated",
    },
    {
      function: "authz.is_platform_for",
      args: "uuid, text",
      role: "authenticated",
    },
    { function: "authz.member_organization_ids", role: "authenticated" },
    { function: "authz.member_project_ids", role: "authenticated" },
    {
      function: "authz.member_organization_ids_for",
      args: "uuid",
      role: "supabase_auth_admin",
    },
    {
      function: "authz.member_project_ids_for",
      args: "uuid",
      role: "supabase_auth_admin",
    },
    { function: "authz.can_assign", args: "uuid, text", role: "authenticated" },
    {
      function: "authz.can_assign_for",
      args: "uuid, uuid, text",
      role: "authenticated",
    },
  ],
  permissions: [
    {
      key: "documents.read",
      sqlComplete: true,
      scopes: ["organization", "project"],
    },
    { key: "documents.write", sqlComplete: true, scopes: ["organization"] },
    { key: "documents.own", sqlComplete: false, scopes: ["organization"] },
    { key: "members.invite", sqlComplete: true, scopes: ["organization"] },
    { key: "members.manage", sqlComplete: true, scopes: ["organization"] },
    { key: "platform.admin", sqlComplete: true },
  ],
  memberships: [
    {
      table: "authz.memberships",
      userColumn: "user_id",
      scope: { column: "scope" },
      idColumn: "scope_id",
    },
  ],
  decidingColumns: ["authz.memberships.user_id", "authz.memberships.role"],
  tokenHook: {
    function: "authz.access_token_hook",
    tenantClaim: "tenant_id",
    ownedClaims: ["memberships", "tenant_id"],
    registeredClaims: [
      { name: "features", function: "better_supabase.feature_claims" },
    ],
    budget: {
      claims: ["memberships"],
      bytes: 1024,
      truncatedClaim: "memberships_truncated",
    },
    markers: {
      hook: "-- authz: access token hook",
      grants: "-- authz: hook grants",
    },
    grantsCommand: "authz hook grants",
  },
};

/** `stubProvider` with fields replaced, or removed with `undefined`. */
export function withProvider(patch: {
  readonly [K in keyof AuthorizationProvider]?:
    | AuthorizationProvider[K]
    | undefined;
}): AuthorizationProvider {
  const provider: Record<string, unknown> = { ...stubProvider, ...patch };
  for (const [key, value] of Object.entries(patch))
    if (value === undefined) delete provider[key];
  // SAFETY: every key is stubProvider's or the patch's, and removed keys are optional.
  return provider as unknown as AuthorizationProvider;
}

/** `stubProvider` as the `provider` access model sees it in a module layout. */
export const moduleProvider: ModuleAccessProvider = {
  name: "stub",
  scope: "organization",
  idType: "uuid",
  functions: stubProvider.functions,
};

/** `moduleProvider` with only the caller's templates: no `_for` and no assignment rule. */
export const callerOnlyProvider: ModuleAccessProvider = {
  ...moduleProvider,
  functions: {
    idsWith: stubProvider.functions.idsWith,
    isPlatform: stubProvider.functions.isPlatform,
  },
};
