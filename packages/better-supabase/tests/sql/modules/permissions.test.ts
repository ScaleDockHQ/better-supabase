import { describe, expect, it } from "vitest";

import type {
  AccessBlockConfig,
  AnyBlocksConfig,
} from "../../../src/config/blocks.ts";
import type { BlockSqlAccessProvider } from "../../../src/sql/module-types.ts";

import { DEFAULT_ROLES } from "../../../src/sql/modules/permissions-model.ts";
import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";
import {
  callerOnlyProvider,
  moduleProvider,
} from "../../fixtures/authorization-provider.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";

const access = (config: AccessBlockConfig, tenant?: object) =>
  moduleBody("permissions", {
    modules: {
      permissions: config,
      ...(tenant ? { memberships: tenant } : {}),
    },
  })!;

const PROVIDER = moduleProvider;
const CALLER_ONLY = callerOnlyProvider;

const provider = (
  config: AccessBlockConfig = {},
  accessProvider: BlockSqlAccessProvider = PROVIDER,
) =>
  moduleBody("permissions", {
    modules: { permissions: { model: "provider", ...config } },
    accessProvider,
  })!;

const CATALOG: AccessBlockConfig = {
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
    const sql = SQL_MODULES["permissions"]!.sql;

    for (const role of Object.keys(DEFAULT_ROLES)) {
      expect(sql).toContain(`when '${role}' then array[`);
    }

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

  it("runs over the app's role, permission and override catalog", () => {
    const modules: AnyBlocksConfig = {
      permissions: CATALOG,
      memberships: {
        tables: { memberships: "public.organization_users" },
        columns: {
          memberships: { tenant: "organization_id", role: "role_id" },
        },
      },
    };

    const sql = renderBlocks(["permissions"], {
      modules,
      ownTables: ownTablesOf(modules),
    }).find((file) => file.module === "permissions")!.contents;

    expect(sql).not.toMatch(/create table if not exists "/);
    expect(sql).toContain(
      'from "public"."organization_permission_overrides" o',
    );
    expect(sql).toContain('bool_and(o."granted")');
    expect(sql).toContain('from "public"."user_roles" a');
    expect(sql).toContain('from "public"."organization_users" m');
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
    const sql = moduleBody("permissions", {
      modules: { permissions: { model: "provider", idType: "text" } },
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

    const sql = moduleBody("permissions", {
      modules: { permissions: { model: "provider" } },
      accessProvider: { ...PROVIDER, suspension },
    })!;

    expect(sql).toContain(
      `not exists (select 1 from "public"."organizations" t where t."id" = tenant_disabled.tenant and t."state"::text in ('active', 'trial'))`,
    );
    expect(sql).toContain(
      `not exists (select 1 from "public"."profiles" u where u."id" = user_disabled.user_id and u."banned_at" is null)`,
    );

    const explicit = moduleBody("permissions", {
      modules: {
        permissions: {
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

    const roles = moduleBody("permissions", {
      modules: { permissions: { model: "roles" } },
      accessProvider: { ...PROVIDER, suspension },
    })!;

    expect(roles).not.toContain("banned_at");
  });

  it("refuses a disabled row without a column that says so", () => {
    const render = (row: object) =>
      moduleBody("permissions", {
        modules: {
          permissions: {
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
      moduleBody("permissions", {
        modules: {
          permissions: {
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
      modules: { permissions: { model: "provider" } },
      accessProvider: PROVIDER,
    })!;

    expect(invitations).toContain(
      "better_supabase.can_user(invite.\"invited_by\", 'organization'",
    );
    expect(invitations).toContain(
      'better_supabase.can_assign_as(invite."invited_by"',
    );

    const notifications = (accessProvider: BlockSqlAccessProvider) =>
      renderBlocks(["notifications", "permissions"], {
        modules: { permissions: { model: "provider" } },
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
      moduleBody("permissions", {
        modules: { permissions: { model: "provider", idType: "uuid" } },
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

  it("renders member_can_while_deleting without the disabled-tenant check in every model", () => {
    const body = (sql: string, name: string) =>
      sql
        .slice(sql.indexOf(`function better_supabase.${name}(`))
        .split("$$;")[0]!;

    const custom = access({
      model: "custom",
      functions: {
        can: "public.authorize({scope}, {id}, {permission})",
        tenantIdsWith: "public.ids_with({permission})",
        isPlatform: "public.is_staff({permission})",
        canAssign: "public.may_assign({tenant}, {role})",
      },
    });

    for (const sql of [access({}), access(CATALOG), provider(), custom]) {
      expect(body(sql, "member_can")).toContain("tenant_disabled(tenant)");
      const deleting = body(sql, "member_can_while_deleting");
      expect(deleting).toContain("user_disabled(member)");
      expect(deleting).not.toContain("tenant_disabled");
      expect(sql).toContain(
        "grant execute on function better_supabase.member_can_while_deleting(uuid, uuid, text) to service_role, supabase_auth_admin;",
      );
    }
  });

  it("answers my_permissions through can() when keys are passed, in every model", () => {
    const models = [
      SQL_MODULES["permissions"]!.sql,
      provider(),
      access({
        model: "custom",
        functions: {
          can: "public.authorize({id}, {permission})",
          tenantIdsWith: "public.ids_with({permission})",
          isPlatform: "public.is_admin({permission})",
          canAssign: "public.may_assign({tenant}, {role})",
        },
      }),
    ];

    for (const sql of models) {
      expect(sql).toContain(
        "create or replace function better_supabase.my_permissions(tenant uuid, keys text[] default null)",
      );
      expect(sql).toContain(
        "where better_supabase.can('tenant', my_permissions.tenant, k)",
      );
      expect(sql).toContain(
        "better_supabase.member_permissions(auth.uid(), my_permissions.tenant)",
      );
      expect(sql).toContain(
        "grant execute on function better_supabase.my_permissions(uuid, text[]) to anon, authenticated, service_role;",
      );
    }
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
    expect(sql).toContain(
      "better_supabase.permission_claims(permission_claims.user_id) -> (permission_claims.tenant::text)",
    );
    expect(() => access({ model: "custom" })).toThrow(
      /needs blocks.permissions.functions.can, tenantIdsWith, isPlatform, canAssign/,
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

    const withTenant = renderBlocks(["memberships", "permissions"], {
      modules: { permissions: { model: "provider" } },
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

  it("reads and overrides catalog roles only under the catalog model", () => {
    const sql = access({ model: "catalog" });

    expect(sql).toContain(
      'create or replace function "better_supabase"."list_roles"(tenant uuid)',
    );
    expect(sql).toContain(
      'create or replace function "better_supabase"."set_permission_override"(tenant uuid, role text, permission text, granted boolean)',
    );
    expect(sql).toContain(
      "better_supabase.member_can(auth.uid(), tenant, 'roles.manage')",
    );
    expect(sql).toContain("better_supabase.can_assign(tenant, v_role::text)");
    expect(sql).toContain("PERMISSIONS_SELF_LOCKOUT");

    const roles = access({ model: "roles" });
    expect(roles).toContain(
      'drop function if exists "better_supabase"."list_roles"(uuid);',
    );
    expect(roles).not.toContain(
      'function "better_supabase"."list_roles"(tenant',
    );
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

  it("keeps only the keys the provider marks sqlComplete", () => {
    const withFunctions = {
      ...PROVIDER,
      functions: {
        ...PROVIDER.functions,
        permissionsFor: "authz.permissions_for({user}, {tenant})",
      },
    };

    expect(
      provider({}, { ...withFunctions, sqlCompleteKeys: ["a.read", "b.it's"] }),
    ).toContain(
      "then coalesce(array(select k from unnest(coalesce((authz.permissions_for(member, tenant)), '{}'::text[])) as k where k = any(array['a.read', 'b.it''s']::text[])), '{}'::text[])",
    );
    expect(provider({}, { ...withFunctions, sqlCompleteKeys: [] })).toContain(
      "then '{}'::text[]",
    );
  });

  it("leaves the permissions claim to a hook that owns it", () => {
    const owned = provider({}, { ...PROVIDER, ownsPermissions: true });

    expect(owned).toContain(
      `-- "permissions" itself, so leave it out of any other hook.`,
    );
    expect(owned).not.toContain("jsonb_set(event, '{claims,permissions}'");

    const marked = provider({}, { ...PROVIDER, truncatedClaim: "partial" });

    expect(marked).toContain("jsonb_set(event, '{claims,partial}', 'true')");
    expect(marked).toContain("jsonb_set(event, '{claims,permissions}', keys)");
  });

  it("keeps both empty without permissionsFor", () => {
    const sql = provider();
    expect(sql).toMatch(
      /function better_supabase\.member_permissions[\s\S]*?select '\{\}'::text\[\]/,
    );
    expect(sql).toContain(
      "better_supabase.permission_claims(permission_claims.user_id) -> (permission_claims.tenant::text)",
    );
  });
});
