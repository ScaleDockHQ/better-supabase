import { describe, expect, it } from "vitest";

import type { AccessKitConfig } from "../../../src/config/kits.ts";

import { moduleBody, SQL_MODULES } from "../../../src/sql/kit.ts";
import { DEFAULT_ROLES } from "../../../src/sql/modules/access-model.ts";

const access = (config: AccessKitConfig, tenant?: object) =>
  moduleBody("access", {
    kits: { access: config, ...(tenant ? { tenant } : {}) },
  })!;

const CATALOG: AccessKitConfig = {
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

  it("maps the permdock model onto PermDock's helpers", () => {
    const sql = access({ model: "permdock", permdock: { scope: "team" } });
    expect(sql).toContain('"permdock"."permitted_team_ids"(permission)');
    expect(sql).toContain('"permdock".permdock_has(permission)');
    const custom = access({
      model: "permdock",
      permdock: { schema: "authz" },
      functions: { canAssign: "public.may_assign({tenant}, {role})" },
    });
    expect(custom).toContain('"authz"."permitted_organization_ids"');
    expect(custom).toContain(
      "public.may_assign(can_assign.tenant, can_assign.role)",
    );
  });

  it("wraps the app's functions in the custom model", () => {
    const sql = access({
      model: "custom",
      functions: {
        can: "public.authorize_scope({scope}::public.scope_type, {id}, {permission})",
        tenantIdsWith: "public.org_ids_with_permission({permission})",
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
      "from public.org_ids_with_permission(tenant_ids_with.permission) as t(id)",
    );
    expect(sql).toContain("public.is_system_user_with(permission)");
    expect(sql).toContain("public.user_can(member, tenant, permission)");
    expect(sql).toContain("public.permission_claims(user_id)");
    expect(() => access({ model: "custom" })).toThrow(
      /needs kits.access.functions.can, tenantIdsWith, isPlatform/,
    );
    expect(() =>
      access({
        model: "custom",
        functions: {
          can: "x({nope})",
          tenantIdsWith: "y()",
          isPlatform: "z()",
        },
      }),
    ).toThrow(/\{nope\} is not available/);
  });

  it("renders the id type in every signature", () => {
    const sql = access({ idType: "bigint" }, { idType: "bigint" });
    expect(sql).toContain("can(text, bigint, text)");
    expect(sql).toContain("returns setof bigint");
  });
});
