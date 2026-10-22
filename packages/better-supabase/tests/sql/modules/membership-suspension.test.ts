import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { adoptedColumnProblems } from "../../../src/sql/adopted-columns.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const render = (modules: AnyBlocksConfig, names = Object.keys(modules)) => {
  const files = renderBlocks(names, {
    modules,
    accessProvider: moduleProvider,
  });

  return (module: string): string =>
    files.find((file) => file.module === module)?.contents ?? "";
};

const ADOPTED: AnyBlocksConfig = {
  memberships: {
    mode: "adopt",
    tables: { memberships: "public.organization_users" },
    columns: { memberships: { lastUsedAt: null, updatedAt: null } },
  },
  permissions: {},
  organizations: {
    mode: "adopt",
    tables: { organizations: "public.organizations" },
    columns: { organizations: { createdBy: null, deletedAt: null } },
  },
};

const SUSPENDABLE: AnyBlocksConfig = {
  ...ADOPTED,
  memberships: {
    ...ADOPTED["memberships"],
    columns: {
      memberships: {
        lastUsedAt: null,
        updatedAt: null,
        disabledAt: "suspended_at",
      },
    },
  },
};

describe("membership suspension", () => {
  it("adds the column to the managed memberships table and reads it everywhere", () => {
    const sql = render({ memberships: {}, permissions: {}, organizations: {} });
    expect(sql("memberships")).toContain(
      'alter table "better_supabase"."memberships" add column if not exists "disabled_at" timestamptz;',
    );
    expect(sql("memberships")).toMatch(
      /member_organization_ids[\s\S]*and m\."disabled_at" is null\n\$\$;/,
    );
    expect(sql("memberships")).toMatch(
      /membership_claims[\s\S]*and m\."disabled_at" is null\n\$\$;/,
    );
    expect(sql("permissions")).toContain(
      'm."user_id" = member_can.member and m."disabled_at" is null',
    );
    expect(sql("permissions")).toMatch(
      /tenant_ids_with[\s\S]*tenant_disabled\(m\."organization_id"\) and m\."disabled_at" is null/,
    );
    expect(sql("permissions")).toContain(
      'm."user_id" = can_assign_as.member and m."disabled_at" is null',
    );
    expect(sql("organizations")).toContain(
      'create or replace function "better_supabase"."suspend_member"(organization uuid, member uuid)',
    );
    expect(sql("organizations")).toContain(
      "returns table (user_id uuid, role text, disabled_at timestamptz)",
    );
  });

  it("leaves an adopted table alone until the column is mapped", () => {
    const sql = render(ADOPTED);
    expect(sql("memberships")).not.toContain('"disabled_at"');
    expect(sql("permissions")).not.toContain('"disabled_at"');
    expect(sql("organizations")).toContain(
      'drop function if exists "better_supabase"."suspend_member"(uuid, uuid);',
    );
    expect(sql("organizations")).not.toContain(
      'create or replace function "better_supabase"."suspend_member"',
    );
    expect(sql("organizations")).toContain(
      "returns table (user_id uuid, role text)",
    );
    expect(
      adoptedColumnProblems(
        ADOPTED,
        [
          {
            text: "create table public.organization_users (organization_id uuid, user_id uuid, role text, created_at timestamptz);\ncreate table public.organizations (id uuid, name text, slug text, created_at timestamptz, updated_at timestamptz, disabled_at timestamptz);",
          },
        ],
        ["public"],
      ),
    ).toEqual([]);
  });

  it("reads a mapped column and guards owners and role changes", () => {
    const sql = render(SUSPENDABLE);
    const organizations = sql("organizations");
    expect(sql("memberships")).not.toContain("add column");
    expect(sql("memberships")).toContain('and m."suspended_at" is null');
    expect(organizations).toContain(
      `"role" = 'owner' and m."suspended_at" is null`,
    );
    expect(organizations).toContain(
      'after update of "role", "organization_id", "suspended_at" or delete',
    );
    expect(organizations).toContain(
      'and new."suspended_at" is not distinct from old."suspended_at" then',
    );
    expect(organizations).toContain("hint = 'ORGANIZATION_MEMBER_SUSPENDED'");
    expect(organizations).toContain(
      `update "public"."organization_users" set "suspended_at" = now()`,
    );
    expect(organizations).toContain(
      `update "public"."organization_users" set "suspended_at" = null`,
    );
    expect(organizations).toContain("You cannot suspend yourself");
    expect(organizations).toContain("hint = 'ORGANIZATION_OWNER_REQUIRED'");
    expect(organizations).toContain("'members.remove'");
    expect(organizations).toContain(
      'grant execute on function "better_supabase"."resume_member"(uuid, uuid) to authenticated, service_role;',
    );
  });

  it("checks its own permission key and writes audit events", () => {
    const sql = render({
      ...SUSPENDABLE,
      organizations: {
        ...SUSPENDABLE["organizations"],
        permissions: { suspendMember: "members.suspend" },
      },
      audit: {},
    });

    const organizations = sql("organizations");
    expect(organizations).toContain("'members.suspend'");
    expect(organizations).toContain(
      "event_type => 'organization.member_suspended'",
    );
    expect(organizations).toContain(
      "event_type => 'organization.member_resumed'",
    );
  });

  it("follows a renamed removeMember key unless suspendMember is set", () => {
    const sql = render({
      ...SUSPENDABLE,
      organizations: {
        ...SUSPENDABLE["organizations"],
        permissions: { removeMember: "member.remove" },
      },
    });

    const organizations = sql("organizations");
    expect(organizations).not.toContain("'members.remove'");
    expect(
      organizations.slice(organizations.indexOf("suspend_member")),
    ).toContain("'member.remove'");
  });

  it("keeps suspended members out of the provider and custom models", () => {
    const provider = render({
      ...SUSPENDABLE,
      permissions: { model: "provider" },
    })("permissions");

    expect(provider).toContain(
      'and not exists (select 1 from "public"."organization_users" sm where sm."organization_id" = tenant and sm."user_id" = member and sm."suspended_at" is not null)',
    );
    expect(provider).toContain(
      'sm."organization_id" = t.id::uuid and sm."user_id" = auth.uid() and sm."suspended_at" is not null',
    );

    const custom = render({
      ...SUSPENDABLE,
      permissions: {
        model: "custom",
        functions: {
          can: "public.can({scope}, {id}, {permission})",
          canUser: "public.can_user({user}, {scope}, {id}, {permission})",
          tenantIdsWith: "public.ids_with({permission})",
          isPlatform: "public.is_platform({permission})",
          canAssign: "true",
        },
      },
    })("permissions");

    expect(custom).toContain(
      'then not exists (select 1 from "public"."organization_users" sm where sm."organization_id" = tenant and sm."user_id" = member and sm."suspended_at" is not null) and coalesce((public.can_user(',
    );
  });
});
