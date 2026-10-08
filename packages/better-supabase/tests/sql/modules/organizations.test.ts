import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import {
  moduleBody,
  renderModules,
  resolveModules,
} from "../../../src/sql/registry.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const CENTRAKIT: ModulesConfig = {
  access: { model: "catalog", platformClaim: "system_permissions" },
  tenant: {
    mode: "adopt",
    tables: { memberships: "public.organization_users" },
    columns: {
      memberships: {
        tenant: "organization_id",
        role: "role_id",
        lastUsedAt: null,
      },
    },
  },
  organizations: {
    mode: "adopt",
    tables: { organizations: "public.organizations" },
    columns: { organizations: { createdBy: null, deletedAt: null } },
    permissions: { removeMember: "organization.members.remove" },
    hooks: {
      schema: "public",
      functions: { after_organization_create: "seed_organization" },
    },
    options: {
      attributes: ["website", "default_currency"],
      reservedSlugs: ["app"],
    },
  },
};

const body = (modules: ModulesConfig) =>
  moduleBody("organizations", { modules, accessProvider: moduleProvider })!;

describe("organizations module", () => {
  it("lists the caller's organizations, members and invitations", () => {
    const sql = renderModules(["organizations", "invitations"], {
      modules: { invitations: {} },
    }).find((file) => file.module === "organizations")!.contents;
    expect(sql).toContain(
      'function "better_supabase"."list_my_organizations"()',
    );
    expect(sql).toContain('function "better_supabase"."list_members"');
    expect(sql).toContain(
      'function "better_supabase"."list_organization_invitations"',
    );
    expect(body({})).not.toContain("list_organization_invitations");
  });

  it("resolves role keys among the tenant's own roles with a mapped roles.tenant", () => {
    const sql = body({
      access: {
        model: "catalog",
        mode: "adopt",
        tables: { roles: "public.roles" },
        columns: { roles: { tenant: "organization_id", scope: null } },
      },
    });
    expect(sql).toContain(
      `(select r."id" from "public"."roles" r where (r."id"::text = (role)::text or r."key" = (role)::text) and (r."organization_id" = organization or r."organization_id" is null) order by (r."id"::text = (role)::text) desc, (r."organization_id" is not null) desc limit 1)`,
    );
    expect(body({ access: { model: "catalog" } })).not.toContain(
      "is not null) desc limit 1",
    );
  });

  it("lets platform keys change roles and remove members", () => {
    const sql = body({
      organizations: {
        permissions: {
          updateRolePlatform: "platform.members.update_role",
          removeMemberPlatform: "platform.members.remove",
        },
      },
    });
    expect(sql).toContain(
      "and not coalesce(better_supabase.is_platform('platform.members.update_role'), false) then\n    raise exception 'Not allowed to change roles'",
    );
    expect(sql).toContain(
      "and not coalesce(better_supabase.is_platform('platform.members.remove'), false) then\n    raise exception 'Not allowed to remove members'",
    );
  });

  it("names the deletion's audit category with auditCategory", () => {
    const audited = (options: Record<string, unknown>) =>
      renderModules(["organizations", "audit"], {
        modules: { organizations: { options } },
      }).find(
        (file) => file.module === "organizations" && file.kind === "schema",
      )!.contents;
    expect(audited({})).toContain("category => 'organization',");
    expect(audited({ auditCategory: "tenancy" })).toContain(
      "category => 'tenancy',",
    );
  });

  it("deletes through data-lifecycle or not at all with deleteMode", () => {
    const lifecycle = renderModules(["organizations", "data-lifecycle"], {
      modules: { organizations: { options: { deleteMode: "lifecycle" } } },
    }).find(
      (file) => file.module === "organizations" && file.kind === "schema",
    )!.contents;
    expect(lifecycle).toContain(
      'perform "better_supabase"."request_organization_deletion"(organization);',
    );
    const none = body({ organizations: { options: { deleteMode: "none" } } });
    expect(none).toContain(
      'drop function if exists "better_supabase"."delete_organization"(uuid);',
    );
    expect(none).not.toContain(
      'create or replace function "better_supabase"."delete_organization"',
    );
    expect(() =>
      body({ organizations: { options: { deleteMode: "lifecycle" } } }),
    ).toThrow(/needs the data-lifecycle module/);
    expect(() =>
      body({ organizations: { options: { deleteMode: "archive" } } }),
    ).toThrow(/must be "hard", "soft", "lifecycle" or "none"/);
  });

  it("transfers ownership in one update and refuses a disabled new owner", () => {
    const sql = body({});
    expect(sql).toContain(
      "if better_supabase.user_disabled(new_owner) then\n    raise exception 'The new owner is disabled'",
    );
    expect(sql).toContain(
      `update "better_supabase"."memberships" m set "role" = case\n      when m."user_id" = new_owner then 'owner'\n      else former_role\n    end`,
    );
  });

  it("checks the own-role rule and both roles' ceilings in update_member_role", () => {
    const sql = body({});
    expect(sql).toContain(
      "if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and member = auth.uid() then",
    );
    expect(sql).toContain(
      "if not better_supabase.can_assign(organization, previous_assignable)\n    or not better_supabase.can_assign(organization, (role)::text) then",
    );
  });

  it("owns its table and makes the creator the owner", () => {
    const sql = body({});
    expect(sql).toContain(
      'create table if not exists "better_supabase"."organizations" (',
    );
    expect(sql).toContain(
      'insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")\n  values (organization, owner, \'owner\');',
    );
    expect(sql).toContain(
      'create constraint trigger "bs_organization_owner" after update of "role", "organization_id", "disabled_at" or delete',
    );
    expect(sql).toMatch(
      /perform 1 from "better_supabase"\."organizations" o .* for update;/,
    );
    expect(sql).toContain('"slug" text not null');
    expect(sql).toContain("coalesce(attrs ->> 'slug', '')");
    expect(sql).toContain("memberships_organization_fkey");
    expect(sql).toContain("on delete cascade not valid;");
    expect(sql).toContain("deferrable initially deferred");
    expect(sql).toContain("hint = 'ORGANIZATION_ROLE_CEILING'");
    expect(sql).not.toContain("better_supabase.trusted");
    expect(sql).toContain(
      "  if not (current_user in ('anon', 'authenticated')) then\n    return new;",
    );
    expect(sql).toMatch(
      /create or replace function "better_supabase"\."guard_membership"\(\)\nreturns trigger\nlanguage plpgsql\nset search_path/,
    );
    expect(sql).toContain(
      'delete from "better_supabase"."organizations" where "id" = organization;',
    );
  });

  it("adopts CentraKit's tables with catalog role ids and its seeding hook", () => {
    const sql = body(CENTRAKIT);
    expect(sql).not.toContain("create table if not exists");
    expect(sql).toContain(
      `'insert into "public"."organizations" ("name", "slug"%s) select r."name", r."slug"%s from`,
    );
    expect(sql).toContain(
      "from unnest(array['website', 'default_currency']) c\n  where attrs ? c;",
    );
    expect(sql).toContain(
      'select r."id" from "better_supabase"."roles" r where (r."id"::text = (\'owner\')::text',
    );
    expect(sql).toContain(
      `to_regprocedure('"public"."seed_organization"(uuid, uuid)')`,
    );
    expect(sql).toContain("'organization.members.remove'");
    expect(sql).toContain(`lower(value) = any (array['app']::text[])`);
    expect(sql).toContain('o."disabled_at" is null');
    expect(sql).toContain('on "public"."organization_users"');
  });

  it("soft-deletes, renders without the owner guard and checks its options", () => {
    const soft = body({
      organizations: {
        options: {
          deleteMode: "soft",
          ownerInvariant: false,
        },
      },
    });
    expect(soft).toContain('set "deleted_at" = now()');
    expect(soft).not.toContain("bs_organization_owner");
    expect(soft).toContain("guard_membership");
    expect(() =>
      body({ organizations: { options: { assignmentCeiling: false } } }),
    ).toThrow(/assignmentCeiling/);
    expect(() =>
      body({
        organizations: {
          options: { deleteMode: "soft" },
          columns: { organizations: { deletedAt: null } },
        },
      }),
    ).toThrow(/deleteMode 'soft' needs the deletedAt column/);
    expect(() =>
      body({ organizations: { options: { attributes: ["x; drop"] } } }),
    ).toThrow(/is not a valid column/);
  });

  it("leaves role checks to an external guard on request", () => {
    const adopted: ModulesConfig = {
      tenant: {
        mode: "adopt",
        tables: { memberships: "public.team_members" },
      },
    };
    const external = body({
      ...adopted,
      organizations: { options: { assignmentGuard: "external" } },
    });
    expect(external).not.toContain(
      'create or replace function "better_supabase"."guard_membership"',
    );
    expect(external).toContain(
      'drop trigger if exists "bs_organization_role_guard" on "public"."team_members";',
    );
    expect(external).toContain("bs_organization_owner");
    expect(external).toContain("better_supabase.can_assign(organization,");
    expect(() =>
      body({ organizations: { options: { assignmentGuard: "external" } } }),
    ).toThrow(/needs an adopted table/);
    expect(() =>
      body({ organizations: { options: { assignmentGuard: "none" } } }),
    ).toThrow(/must be "module" or "external"/);
  });

  it("lets platform staff update and delete with their own keys", () => {
    const sql = body({
      organizations: {
        permissions: {
          updatePlatform: "platform.organization.update",
          deletePlatform: "platform.organization.delete",
        },
      },
    });
    expect(sql).toContain(
      "and not coalesce(better_supabase.is_platform('platform.organization.update'), false)",
    );
    expect(sql).toContain(
      "and not coalesce(better_supabase.is_platform('platform.organization.delete'), false)",
    );
    expect(body({})).not.toContain("platform.organization");
  });

  it("checks a create permission when one is configured", () => {
    expect(
      body({
        organizations: { permissions: { create: "organizations.create" } },
      }),
    ).toContain("better_supabase.is_platform('organizations.create')");
    expect(body({})).not.toContain("Not allowed to create an organization");
  });

  it("installs after tenant and access", () => {
    const names = resolveModules(["organizations"]).map((m) => m.name);
    expect(names).toEqual(["updated-at", "tenant", "access", "organizations"]);
    expect(
      moduleBody("organizations", {
        modules: { organizations: { mode: "custom" } },
      }),
    ).toBeUndefined();
  });
});

describe("roles through a lookup table", () => {
  const THROUGH: ModulesConfig = {
    access: {
      model: "provider",
    },
    tenant: {
      mode: "adopt",
      tables: { memberships: "public.team_members" },
      columns: { memberships: { tenant: "team_id", role: "role_id" } },
      options: {
        roleThrough: { table: "public.team_roles", id: "id", column: "key" },
      },
    },
  };

  it("stores role ids and checks and assigns by role name", () => {
    const sql = body(THROUGH);
    expect(sql).toContain(
      `can_assign(target_tenant, (select r."key"::text from "public"."team_roles" r where r."id"::text = (target_role)::text))`,
    );
    expect(sql).toContain(
      `set "role_id" = (select r."id" from "public"."team_roles" r where (r."id"::text = (role)::text or r."key"::text = (role)::text)`,
    );
    expect(sql).toContain("hint = 'ORGANIZATION_ROLE_UNKNOWN'");
    const tenant = moduleBody("tenant", {
      modules: THROUGH,
      accessProvider: moduleProvider,
    })!;
    expect(tenant).toContain(
      `jsonb_build_array((select r."key"::text from "public"."team_roles" r where r."id"::text = (m."role_id")::text))`,
    );
    const invitations = moduleBody("invitations", {
      modules: { ...THROUGH, invitations: { mode: "adopt" } },
      accessProvider: moduleProvider,
    })!;
    expect(invitations).toContain(
      `if (select r."id" from "public"."team_roles" r where (r."id"::text = (invitee_role)::text`,
    );
    expect(invitations).toContain(
      `can_assign(tenant, (select r."key"::text from "public"."team_roles" r where r."id"::text = (((select r."id" from "public"."team_roles" r where (`,
    );
  });

  it("rejects roleThrough on a managed table or in the wrong shape", () => {
    expect(() =>
      moduleBody("tenant", {
        modules: {
          tenant: {
            options: {
              roleThrough: { table: "public.roles", id: "id", column: "key" },
            },
          },
        },
      }),
    ).toThrow(/describes an adopted memberships table/);
    expect(() =>
      moduleBody("tenant", {
        modules: {
          tenant: { mode: "adopt", options: { roleThrough: "public.roles" } },
        },
      }),
    ).toThrow(/roleThrough must be/);
  });

  it("takes the role lookup from the provider's role sources", () => {
    const { options: _options, ...tenant } = THROUGH["tenant"]!;
    const layout = {
      modules: { ...THROUGH, tenant },
      accessProvider: {
        ...moduleProvider,
        roleSources: [
          {
            table: "public.team_members",
            role: {
              column: "role_id",
              through: { table: "public.team_roles", id: "id", column: "key" },
            },
          },
        ],
      },
    };
    expect(moduleBody("tenant", layout)).toContain(
      `from "public"."team_roles" r where r."id"::text = (m."role_id")::text`,
    );
    expect(
      moduleBody("tenant", {
        ...layout,
        modules: {
          ...layout.modules,
          tenant: { ...tenant, columns: { memberships: { role: "role" } } },
        },
      }),
    ).not.toContain("team_roles");
  });
});
