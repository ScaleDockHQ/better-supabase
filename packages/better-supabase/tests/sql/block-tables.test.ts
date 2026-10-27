import { describe, expect, it } from "vitest";

import { resolveConfig } from "../../src/config/index.ts";
import { blockTables } from "../../src/sql/index.ts";

describe("blockTables", () => {
  it("returns the default names without renames", () => {
    const tables = blockTables(
      resolveConfig({ blocks: { memberships: {}, organizations: {} } }, "/app"),
    );

    expect(tables.memberships).toEqual({
      schema: "better_supabase",
      name: "memberships",
      table: "better_supabase.memberships",
      columns: {
        tenant: "organization_id",
        user: "user_id",
        role: "role",
        disabledAt: "disabled_at",
      },
    });
    expect(tables.organizations?.table).toBe("better_supabase.organizations");
    expect(tables.membershipRoles).toBeUndefined();
  });

  it("resolves table and column renames like the rendered SQL", () => {
    const tables = blockTables(
      resolveConfig(
        {
          blocks: {
            memberships: {
              tables: { memberships: "public.team_members" },
              columns: { memberships: { tenant: "team_id" } },
            },
            organizations: { columns: { organizations: { slug: "handle" } } },
          },
        },
        "/app",
      ),
    );

    expect(tables.memberships?.table).toBe("public.team_members");
    expect(tables.memberships?.columns.tenant).toBe("team_id");
    expect(tables.organizations?.columns.slug).toBe("handle");
    expect(tables.byBlock["memberships"]?.["memberships"]?.table).toBe(
      "public.team_members",
    );
  });

  it("lists membership_roles when memberships hold many roles", () => {
    const tables = blockTables(
      resolveConfig(
        {
          blocks: {
            memberships: {
              options: { roles: { many: true } },
              columns: { memberships: { tenant: "team_id" } },
            },
          },
        },
        "/app",
      ),
    );

    expect(tables.membershipRoles).toEqual({
      schema: "better_supabase",
      name: "membership_roles",
      table: "better_supabase.membership_roles",
      columns: { tenant: "team_id", user: "user_id", role: "role" },
    });
    expect(tables.organizations).toBeUndefined();
  });

  it("keys every instance by its name, with prefixed tables", () => {
    const tables = blockTables(
      resolveConfig(
        {
          blocks: {
            tags: {},
            labels: { block: "tags", entities: { tag: "label" } },
          },
        },
        "/app",
      ),
    );

    expect(tables.byBlock["tags"]?.["taggings"]?.table).toBe(
      "better_supabase.taggings",
    );
    expect(tables.byBlock["labels"]?.["taggings"]?.columns["tag"]).toBe(
      "label_id",
    );
    expect(tables.memberships).toBeUndefined();
  });
});
