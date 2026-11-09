import { describe, expect, it } from "vitest";

import { compactBootstrapPermissions } from "../../src/core/bootstrap-permissions.ts";
import { can } from "../../src/react/permissions.ts";

describe("can", () => {
  const permissions = {
    apiVersion: 1 as const,
    tenants: { acme: ["customers.read"] },
    platform: ["admin.audit"],
  };

  it("matches a tenant key, a platform key and the compact form", () => {
    expect(can(permissions, "customers.read", "acme")).toBe(true);
    expect(can(permissions, "customers.read", "other")).toBe(false);
    expect(can(permissions, "admin.audit")).toBe(true);
    expect(can(undefined, "customers.read")).toBe(false);

    expect(compactBootstrapPermissions(permissions).form).toBe("compact");
  });
});
