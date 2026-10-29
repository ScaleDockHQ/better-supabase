import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";

const MANY: AnyBlocksConfig = {
  memberships: { options: { roles: { many: true } } },
  invitations: {
    options: { defaultRole: "admin", onAccept: { roles: true, teams: true } },
  },
};

const render = (modules: AnyBlocksConfig) =>
  renderBlocks(
    ["memberships", "permissions", "organizations", "invitations", "teams"],
    { modules },
  );

const fileOf = (files: ReturnType<typeof render>, module: string): string =>
  files
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("memberships roles.many", () => {
  const files = render(MANY);
  const memberships = fileOf(files, "memberships");

  it("renders the golden SQL", async () => {
    await expect(
      ["memberships", "permissions", "organizations", "invitations"]
        .map((module) => `-- ==== ${module}\n${fileOf(files, module)}`)
        .join("\n"),
    ).toMatchFileSnapshot("../__golden__/memberships-many-roles.sql");
  });

  it("keeps a role set next to the primary role", () => {
    expect(memberships).toContain(
      'create table if not exists "better_supabase"."membership_roles"',
    );
    expect(memberships).toContain(
      'primary key ("organization_id", "user_id", "role")',
    );
    expect(memberships).toContain("on delete cascade");
    expect(memberships).toContain(
      'insert into "better_supabase"."membership_roles"',
    );
    expect(memberships).toContain(
      "order by array_position(array['owner', 'admin', 'member', 'viewer']::text[], r.\"role\")",
    );
  });

  it("answers role checks and claims from the set", () => {
    expect(memberships).toMatch(
      /member_organization_ids\.roles is null or exists \(select 1 from "better_supabase"\."membership_roles" mr/,
    );
    expect(memberships).toMatch(
      /has_organization_role\.roles is null or exists \(select 1 from "better_supabase"\."membership_roles" mr/,
    );
    expect(memberships).toContain(
      "'roles', (select coalesce(jsonb_agg(r.\"role\" order by r.\"role\"), '[]'::jsonb)",
    );
    expect(memberships).toContain('array_agg(r."role" order by');
  });

  it("unions the permissions of every role", () => {
    const permissions = fileOf(files, "permissions");

    expect(permissions).toContain(
      'cross join unnest(better_supabase.role_permissions(mr."role")) k(key)',
    );
    expect(permissions).toContain('better_supabase.role_grants(mr."role", ');
  });

  it("adds and removes roles, and transfers ownership within the set", () => {
    const organizations = fileOf(files, "organizations");

    expect(organizations).toContain(
      'function "better_supabase"."add_member_role"(organization uuid, member uuid, role text)',
    );
    expect(organizations).toContain("ORGANIZATION_ROLE_LAST");
    expect(organizations).toContain(
      'grant execute on function "better_supabase"."remove_member_role"(uuid, uuid, text) to authenticated, service_role;',
    );
    expect(organizations).toMatch(
      /insert into "better_supabase"\."membership_roles" \("organization_id", "user_id", "role"\) values \(organization, new_owner, 'owner'\)/,
    );
    expect(organizations).toContain("roles text[]");
  });

  it("stores the invitation's extra roles and teams and grants them on accept", () => {
    const invitations = fileOf(files, "invitations");

    expect(invitations).toContain(
      'add column if not exists "extra_roles" text[]',
    );
    expect(invitations).toContain('add column if not exists "team_ids" uuid[]');
    expect(invitations).toContain("on_accept jsonb default null");
    expect(invitations).toContain("INVITATION_TEAM_UNKNOWN");
    expect(invitations).toContain('unnest(invite."extra_roles")');
    expect(invitations).toContain('unnest(invite."team_ids")');
    expect(invitations).toContain("invitee_role text default 'admin'");
    expect(invitations).toContain(
      "invitee_role := coalesce(invitee_role, 'admin');",
    );
  });
});

describe("memberships roles.many off", () => {
  const files = render({});

  it("drops the sync triggers and keeps one role", () => {
    const memberships = fileOf(files, "memberships");

    expect(memberships).not.toContain(
      'create table if not exists "better_supabase"."membership_roles"',
    );
    expect(memberships).toContain(
      'drop function if exists "better_supabase"."membership_roles_from_role"() cascade;',
    );
    expect(memberships).toContain('select array[m."role"]::text[]');
    expect(fileOf(files, "organizations")).toContain(
      'drop function if exists "better_supabase"."add_member_role"(uuid, uuid, text);',
    );
    expect(fileOf(files, "invitations")).not.toContain("on_accept jsonb");
  });
});

describe("memberships roles.many with app-defined roles", () => {
  const files = render({
    ...MANY,
    permissions: {
      model: "custom",
      functions: {
        can: "app.can({permission})",
        tenantIdsWith: "app.tenant_ids_with({permission})",
        isPlatform: "app.is_platform({permission})",
        canAssign: "app.can_assign({tenant}, {role})",
      },
    },
  });

  it("stores roles outside blocks.permissions.roles", () => {
    const memberships = fileOf(files, "memberships");

    expect(memberships).toContain(
      "drop constraint if exists membership_roles_role_check",
    );
    expect(memberships).not.toContain(
      "add constraint membership_roles_role_check",
    );
  });

  it("checks on_accept.roles against can_assign only", () => {
    const invitations = fileOf(files, "invitations");

    expect(invitations).toContain("r.role is null or r.role = ''");
    expect(invitations).toContain("better_supabase.can_assign(tenant, r.role)");
    expect(invitations).not.toContain("not (r.role = any (array[");
  });
});

describe("the {roles} placeholder", () => {
  it("passes the assigned role as a one-element array", () => {
    const sql = moduleBody("permissions", {
      modules: {
        permissions: {
          model: "custom",
          functions: {
            can: "app.can({permission})",
            tenantIdsWith: "app.tenant_ids_with({permission})",
            isPlatform: "app.is_platform({permission})",
            canAssign: "app.can_assign_all({tenant}, {roles})",
          },
        },
      },
    })!;

    expect(sql).toContain(
      "app.can_assign_all(can_assign.tenant, array[can_assign.role]::text[])",
    );
  });
});

describe("memberships roles option errors", () => {
  it.each([
    [
      { memberships: { options: { roles: { many: "yes" } } } },
      "must be { many: boolean }",
    ],
    [
      { memberships: { options: { roles: { many: true, other: 1 } } } },
      "must be { many: boolean }",
    ],
    [
      {
        permissions: { model: "catalog" },
        memberships: { options: { roles: { many: true } } },
      },
      "the catalog model and roleThrough store role ids",
    ],
    [
      { invitations: { options: { onAccept: { roles: true } } } },
      "turn on blocks.memberships.options.roles.many",
    ],
    [
      { invitations: { options: { onAccept: { groups: true } } } },
      "must be { roles?: boolean, teams?: boolean }",
    ],
    [
      { invitations: { options: { defaultRole: "guest" } } },
      'defaultRole: "guest" is not one of blocks.permissions.roles',
    ],
  ] as const)("refuses %j", (modules, message) => {
    expect(() => render(modules as AnyBlocksConfig)).toThrow(message);
  });

  it("refuses onAccept.teams without the teams block", () => {
    expect(() =>
      renderBlocks(["memberships", "organizations", "invitations"], {
        modules: { invitations: { options: { onAccept: { teams: true } } } },
      }),
    ).toThrow("install the teams block");
  });
});
