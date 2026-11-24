import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

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

  it("reads the holders from the custom model's holdersOf, or refuses without one", () => {
    const custom = (holdersOf?: string): string =>
      renderBlocks(["notifications"], {
        modules: {
          permissions: {
            model: "custom",
            functions: {
              can: "app.can",
              tenantIdsWith: "app.tenant_ids_with",
              isPlatform: "app.is_platform",
              ...(holdersOf === undefined ? {} : { holdersOf }),
            },
          },
        },
      })
        .map((file) => file.contents)
        .join("\n");

    expect(custom("app.holders_of({permission}, {tenant})")).toContain(
      "select u from app.holders_of((notification ->> 'permission'), v_tenant) as t(u)",
    );
    expect(custom()).toContain("NOTIFICATION_PERMISSION_AUDIENCE_UNAVAILABLE");
  });

  it("refuses a permission audience under a provider without one, and checks channelDefaults", () => {
    const render = (modules: AnyBlocksConfig): string =>
      renderBlocks(["notifications"], { modules })
        .map((file) => file.contents)
        .join("\n");

    expect(render({ permissions: { model: "provider" } })).toContain(
      "NOTIFICATION_PERMISSION_AUDIENCE_UNAVAILABLE",
    );
    expect(() =>
      render({ notifications: { options: { channelDefaults: [] } } }),
    ).toThrow("channelDefaults must map channel names to booleans");
    expect(() =>
      render({ notifications: { options: { channelDefaults: { email: 1 } } } }),
    ).toThrow("channelDefaults.email must be a boolean");
  });
});
