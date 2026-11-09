import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sessionsSql = (
  permissions: { readonly tables?: Record<string, string | null> } = {},
): string =>
  renderBlocks(["sessions", "permissions", "memberships"], {
    modules: {
      sessions: { options: { authzVersions: true } },
      ...(Object.keys(permissions).length === 0 ? {} : { permissions }),
    },
  })
    .filter((file) => file.module === "sessions")
    .map((file) => file.contents)
    .join("\n");

describe("role authorization bumps", () => {
  it("bumps members, platform roles and overrides in one statement", () => {
    const sql = sessionsSql();

    expect(sql).toContain("bump_inserted_role_members");
    expect(sql).toContain("bump_deleted_role_members");
    expect(sql).toContain("bump_updated_role_members");
    expect(sql).toContain("bump_inserted_platform_roles");
    expect(sql).toContain("bump_deleted_platform_roles");
    expect(sql).toContain("bump_override_members");
    expect(sql).toContain("referencing new table as changed");
    expect(sql).toContain("referencing old table as changed");
  });

  it("skips platform roles and overrides when those tables are off", () => {
    const sql = sessionsSql({
      tables: { platformAssignments: null, overrides: null },
    });

    expect(sql).toContain("bump_inserted_role_members");
    expect(sql).not.toContain("bump_inserted_platform_roles");
    expect(sql).not.toContain("bump_override_members");
  });

  it("refuses to turn the role permissions table off", () => {
    expect(() => sessionsSql({ tables: { rolePermissions: null } })).toThrow(
      /rolePermissions is required/,
    );
  });
});
