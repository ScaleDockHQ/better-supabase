import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { moduleBody, resolveModules } from "../../../src/sql/registry.ts";

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
  moduleBody("organizations", { modules })!;

describe("organizations module", () => {
  it("owns its table and makes the creator the owner", () => {
    const sql = body({});
    expect(sql).toContain(
      'create table if not exists "better_supabase"."organizations" (',
    );
    expect(sql).toContain(
      'insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")\n  values (organization, owner, \'owner\');',
    );
    expect(sql).toContain(
      'create constraint trigger "bs_organization_owner" after update of "role", "organization_id" or delete',
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
    expect(sql).toContain(
      "perform set_config('better_supabase.trusted', 'on', true);",
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
      'select r."id" from "better_supabase"."roles" r where r."id"::text = (\'owner\')::text',
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
