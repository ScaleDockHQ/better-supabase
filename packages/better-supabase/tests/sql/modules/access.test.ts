import { describe, expect, it } from "vitest";

import type { AccessModuleConfig } from "../../../src/config/modules.ts";
import type { ModuleAccessProvider } from "../../../src/sql/registry.ts";

import { DEFAULT_ROLES } from "../../../src/sql/modules/access-model.ts";
import {
  moduleBody,
  renderModules,
  SQL_MODULES,
} from "../../../src/sql/registry.ts";
import {
  callerOnlyProvider,
  moduleProvider,
} from "../../fixtures/authorization-provider.ts";

const access = (config: AccessModuleConfig, tenant?: object) =>
  moduleBody("access", {
    modules: { access: config, ...(tenant ? { tenant } : {}) },
  })!;

const PROVIDER = moduleProvider;
const CALLER_ONLY = callerOnlyProvider;

const provider = (
  config: AccessModuleConfig = {},
  accessProvider: ModuleAccessProvider = PROVIDER,
) =>
  moduleBody("access", {
    modules: { access: { model: "provider", ...config } },
    accessProvider,
  })!;

const CATALOG: AccessModuleConfig = {
  mode: "adopt",
  model: "catalog",
  tables: {
    roles: "public.roles",
    permissions: "public.permissions",
    rolePermissions: "public.role_permissions",
    overrides: "public.organization_permission_overrides",
    platformAssignments: "public.user_roles",
  },
  columns: { overrides: { tenant: "organization_id" } },
};

describe("access module", () => {
  it("renders the roles model from the default roles", () => {
    const sql = SQL_MODULES["access"]!.sql;
    for (const role of Object.keys(DEFAULT_ROLES))
      expect(sql).toContain(`when '${role}' then array[`);
    expect(sql).toContain(
      'better_supabase.role_grants(m."role", member_can.permission)',
    );
    expect(sql).toContain("'platform_permissions'");
    expect(sql).toContain(
      "create or replace function better_supabase.can(scope text, scope_id uuid, permission text)",
    );
    expect(sql).toContain("when can.scope in ('organization', 'tenant')");
    expect(sql).not.toMatch(/create table/);
  });

  it("takes roles, the platform claim and the tenant scope from config", () => {
    const sql = access({
      roles: { lead: ["projects.*"], guest: [] },
      platformClaim: "staff",
      options: { scope: "workspace" },
    });
    expect(sql).toContain("when 'lead' then array['projects.*']::text[]");
    expect(sql).toContain("when 'guest' then array[]::text[]");
    expect(sql).toContain("'staff'");
    expect(sql).toContain("when can.scope in ('workspace', 'tenant')");
    expect(access({ roles: {} })).toContain("select '{}'::text[]");
  });

  it("adopts a role, permission and override catalog", () => {
    const sql = access(CATALOG, {
      mode: "adopt",
      tables: { memberships: "public.organization_users" },
      columns: { memberships: { tenant: "organization_id", role: "role_id" } },
    });
    expect(sql).not.toMatch(/create table/);
    expect(sql).toContain(
      'from "public"."organization_permission_overrides" o',
    );
    expect(sql).toContain('bool_and(o."granted")');
    expect(sql).toContain('from "public"."user_roles" a');
    expect(sql).toContain('from "public"."organization_users" m');
    expect(sql).toContain("-- Adopted catalog:");
  });

  it("creates the catalog tables in managed mode and leaves out optional ones", () => {
    const sql = access({
      model: "catalog",
      tables: { overrides: null, platformAssignments: null },
    });
    expect(sql).toContain(
      'create table if not exists "better_supabase"."roles"',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."role_permissions"',
    );
    expect(sql).not.toContain("permission_overrides");
    expect(sql).not.toContain("platform_roles");
    expect(access({ model: "catalog" })).toContain(
      'create table if not exists "better_supabase"."platform_roles"',
    );
  });

  it("maps the provider model onto the provider's templates", () => {
    const sql = provider();
    expect(sql).toContain("authz.ids_organization(permission)");
    expect(sql).toContain("authz.is_platform(permission)");
    expect(sql).toContain(
      "-- The provider model: the authorization provider (stub) decides",
    );
    const custom = provider(
      { functions: { canAssign: "public.may_assign({tenant}, {role})" } },
      CALLER_ONLY,
    );
    expect(custom).toContain(
      "public.may_assign(can_assign.tenant, can_assign.role)",
    );
    expect(provider()).toContain(
      "authz.can_assign(can_assign.tenant, can_assign.role)",
    );
  });

  it("takes the provider's scope and id type", () => {
    const sql = moduleBody("access", {
      modules: { access: { model: "provider", idType: "text" } },
      accessProvider: { ...PROVIDER, scope: "tenant", idType: "text" },
    })!;
    expect(sql).toContain("authz.ids_tenant(permission)");
    expect(sql).toContain("can(scope text, scope_id text, permission text)");
    expect(sql).not.toContain("ids_organization");
  });

  it("disables tenants and users from the provider's suspension rows", () => {
    const suspension = {
      user: { table: "public.profiles", id: "id", disabledAt: "banned_at" },
      tenant: {
        table: "public.organizations",
        id: "id",
        status: "state",
        active: ["active", "trial"],
      },
    };
    const sql = moduleBody("access", {
      modules: { access: { model: "provider" } },
      accessProvider: { ...PROVIDER, suspension },
    })!;
    expect(sql).toContain(
      `not exists (select 1 from "public"."organizations" t where t."id" = tenant_disabled.tenant and t."state"::text in ('active', 'trial'))`,
    );
    expect(sql).toContain(
      `not exists (select 1 from "public"."profiles" u where u."id" = user_disabled.user_id and u."banned_at" is null)`,
    );
    const explicit = moduleBody("access", {
      modules: {
        access: {
          model: "provider",
          disabled: { user: "public.accounts.disabled_at", userKey: "owner" },
        },
      },
      accessProvider: { ...PROVIDER, suspension },
    })!;
    expect(explicit).toContain(
      `exists (select 1 from "public"."accounts" u where u."owner" = user_disabled.user_id and u."disabled_at" is not null)`,
    );
    expect(explicit).toContain(`t."state"::text in ('active', 'trial')`);
    const roles = moduleBody("access", {
      modules: { access: { model: "roles" } },
      accessProvider: { ...PROVIDER, suspension },
    })!;
    expect(roles).not.toContain("banned_at");
  });

  it("refuses a disabled row without a column that says so", () => {
    const render = (row: object) =>
      moduleBody("access", {
        modules: {
          access: {
            disabled: {
              tenant: { table: "public.organizations", id: "id", ...row },
            },
          },
        },
      });
    expect(() => render({})).toThrow(/needs disabledAt, status or both/);
    expect(() => render({ status: "state" })).toThrow(
      /needs the active values/,
    );
    expect(() =>
      moduleBody("access", {
        modules: {
          access: {
            disabled: {
              user: { table: "profiles", id: "id", disabledAt: "x" },
            },
          },
        },
      }),
    ).toThrow(/must be "schema.table"/);
  });

  it("checks a stored user's assignments with canAssignFor", () => {
    expect(provider()).toContain(
      "coalesce((authz.can_assign_for(can_assign_as.member, can_assign_as.tenant, can_assign_as.role)), false)",
    );
    const template = provider(
      {
        functions: {
          canAssignFor: "app.can_assign_for({user}, {tenant}, {role})",
        },
      },
      CALLER_ONLY,
    );
    expect(template).toContain(
      "coalesce((app.can_assign_for(can_assign_as.member, can_assign_as.tenant, can_assign_as.role)), false)",
    );
    const custom = access({
      model: "custom",
      functions: {
        can: "app.can({scope}, {id}, {permission})",
        tenantIdsWith: "app.tenants({permission})",
        isPlatform: "app.platform({permission})",
        canAssign: "app.can_assign({tenant}, {role})",
        canAssignFor: "app.can_assign_for({user}, {tenant}, {role})",
      },
    });
    expect(custom).toContain(
      "create or replace function better_supabase.can_assign_as(member uuid, tenant uuid, role text)",
    );
    expect(provider({}, CALLER_ONLY)).not.toContain("can_assign_as(");
  });

  it("answers for another user through the provider's _for templates", () => {
    const callerOnly = provider({}, CALLER_ONLY);
    expect(callerOnly).toContain("hint = 'ACCESS_CALLER_ONLY'");
    expect(callerOnly).not.toContain("_for(");
    const sql = provider();
    expect(sql).toContain("authz.ids_organization_for(member, permission)");
    expect(sql).toContain("authz.is_platform_for(member, permission)");
    expect(sql).not.toContain("hint = 'ACCESS_CALLER_ONLY'");
    const { isPlatformFor: _, ...partialFunctions } = PROVIDER.functions;
    const partial = provider({}, { ...PROVIDER, functions: partialFunctions });
    expect(partial).toContain("authz.ids_organization_for");
    expect(partial).not.toContain("is_platform_for");
    expect(partial).toContain("hint = 'ACCESS_CALLER_ONLY'");
    const invitations = moduleBody("invitations", {
      modules: { access: { model: "provider" } },
      accessProvider: PROVIDER,
    })!;
    expect(invitations).toContain(
      "better_supabase.can_user(invite.\"invited_by\", 'organization'",
    );
    expect(invitations).toContain(
      'better_supabase.can_assign_as(invite."invited_by"',
    );
    const notifications = (accessProvider: ModuleAccessProvider) =>
      renderModules(["notifications", "access"], {
        modules: { access: { model: "provider" } },
        accessProvider,
      }).find(
        (file) => file.module === "notifications" && file.kind === "schema",
      )!.contents;
    expect(notifications(CALLER_ONLY)).toContain(
      "recipients are not\n  -- filtered by their read permission",
    );
    expect(notifications(PROVIDER)).toContain(
      "coalesce(better_supabase.member_can(x, v_tenant,",
    );
  });

  it("never renders the provider model without a provider", () => {
    expect(() => access({ model: "provider" })).toThrow(
      /needs an authorization provider/,
    );
    expect(() =>
      moduleBody("access", {
        modules: { access: { model: "provider", idType: "uuid" } },
        accessProvider: { ...PROVIDER, scope: "tenant", idType: "text" },
      }),
    ).toThrow(
      /gives scope "tenant" the type text, but the access module renders uuid ids/,
    );
  });

  it("raises 0A000 when the provider model is asked about another user", () => {
    const sql = provider({}, CALLER_ONLY);
    const caller = (name: string) =>
      sql
        .slice(sql.indexOf(`function better_supabase.${name}(`))
        .split("$$;")[0]!;
    for (const name of ["member_can", "can_user"]) {
      expect(caller(name)).toContain("language plpgsql");
      expect(caller(name)).toContain(
        "if member is distinct from auth.uid() then",
      );
      expect(caller(name)).toContain(
        "using errcode = '0A000', hint = 'ACCESS_CALLER_ONLY'",
      );
    }
    expect(sql).not.toContain("null::boolean");
    const roles = access({});
    expect(roles).not.toContain("ACCESS_CALLER_ONLY");
    expect(
      roles.slice(roles.indexOf("function better_supabase.can_user(")),
    ).toMatch(/^[^$]*language sql/);
  });

  it("wraps the app's functions in the custom model", () => {
    const sql = access({
      model: "custom",
      functions: {
        can: "public.authorize_scope({scope}::public.scope_type, {id}, {permission})",
        tenantIdsWith: "public.organization_ids_with_permission({permission})",
        isPlatform: "public.is_system_user_with({permission})",
        canUser: "public.user_can({user}, {id}, {permission})",
        canAssign: "public.may_assign({tenant}, {role})",
        permissionClaims: "public.permission_claims({user})",
      },
    });
    expect(sql).toContain(
      "public.authorize_scope('organization'::public.scope_type, tenant, permission)",
    );
    expect(sql).toContain(
      "from public.organization_ids_with_permission(tenant_ids_with.permission) as t(id)",
    );
    expect(sql).toContain("public.is_system_user_with(permission)");
    expect(sql).toContain("public.user_can(member, tenant, permission)");
    expect(sql).toContain("public.permission_claims(user_id)");
    expect(() => access({ model: "custom" })).toThrow(
      /needs sql.modules.access.functions.can, tenantIdsWith, isPlatform, canAssign/,
    );
    expect(() =>
      access({
        model: "custom",
        functions: {
          can: "x({nope})",
          tenantIdsWith: "y()",
          isPlatform: "z()",
          canAssign: "w()",
        },
      }),
    ).toThrow(/\{nope\} is not available/);
  });

  it("leaves role assignment to the service role without an assignment rule", () => {
    expect(provider({}, CALLER_ONLY)).toMatch(
      /or coalesce\(\(false\), false\)/,
    );
    const withTenant = renderModules(["tenant", "access"], {
      modules: { access: { model: "provider" } },
      accessProvider: CALLER_ONLY,
    })
      .map((file) => file.contents)
      .join("\n");
    expect(withTenant).not.toContain(
      "better_supabase.has_organization_role(can_assign.tenant, array['owner'])",
    );
    expect(withTenant).toContain("Without either, only the service role");
  });

  it("counts tenant overrides when the catalog model checks an assignment", () => {
    const sql = access({ model: "catalog" });
    const canAssign = sql.slice(
      sql.indexOf("function better_supabase.can_assign"),
    );
    expect(canAssign).toContain('"permission_overrides"');
    expect(canAssign).toContain("can_assign_as.tenant as");
  });

  it("keeps tenant and platform roles apart in the managed catalog", () => {
    const sql = access({ model: "catalog" });
    expect(sql).toContain(`check ("scope" in ('tenant', 'platform'))`);
    expect(sql).toContain(`r."scope"::text = 'tenant'`);
    expect(sql).toContain(
      "function better_supabase.platform_can_assign(member uuid, role text)",
    );
    expect(sql).toContain(`r."scope"::text = 'platform'`);
  });

  it("drops platform permissions while a token acts for another user", () => {
    for (const model of ["roles", "catalog"] as const) {
      expect(access({ model })).toContain(
        "(platform_can.member is distinct from auth.uid() or auth.jwt() -> 'act' is null)",
      );
    }
  });

  it("renders the id type in every signature", () => {
    const sql = access({ idType: "bigint" }, { idType: "bigint" });
    expect(sql).toContain("can(text, bigint, text)");
    expect(sql).toContain("returns setof bigint");
  });
});

describe("access module with the provider's permissionsFor", () => {
  it("fills member_permissions and permission_claims from the template", () => {
    const sql = provider(
      {},
      {
        ...PROVIDER,
        functions: {
          ...PROVIDER.functions,
          permissionsFor: "authz.permissions_for({user}, {tenant})",
        },
      },
    );
    expect(sql).toContain(
      "then coalesce((authz.permissions_for(member, tenant)), '{}'::text[])",
    );
    expect(sql).toMatch(
      /function better_supabase\.permission_claims[\s\S]*jsonb_object_agg\(t\.id::text/,
    );
  });

  it("keeps both empty without permissionsFor", () => {
    const sql = provider();
    expect(sql).toMatch(
      /function better_supabase\.member_permissions[\s\S]*?select '\{\}'::text\[\]/,
    );
  });
});
