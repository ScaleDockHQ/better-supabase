import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("notification permission audiences", () => {
  const sql = renderBlocks(["notifications"])
    .map((file) => file.contents)
    .join("\n");

  it("refuses a permission audience when no holders function is configured", () => {
    expect(sql).toContain("NOTIFICATION_PERMISSION_AUDIENCE_UNAVAILABLE");
  });

  it("asks can_user for each member when the roles model has a tenant", () => {
    const withTenant = renderBlocks([
      "permissions",
      "memberships",
      "notifications",
    ])
      .map((file) => file.contents)
      .join("\n");

    expect(withTenant).toContain("NOTIFICATION_PERMISSION_NEEDS_TENANT");
    expect(withTenant).toContain(
      "better_supabase.can_user(m.\"user_id\", 'tenant', v_tenant, notification ->> 'permission')",
    );
  });
});
