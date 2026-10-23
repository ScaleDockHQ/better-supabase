import { describe, expect, it } from "vitest";

import { requireOrganization } from "../../src/core/block-tenant.ts";
import { currentTenant } from "../../src/core/tenant-source.ts";

describe("currentTenant", () => {
  it("reads a fixed id or calls the function each time", () => {
    let tenant: string | undefined = "org-1";

    expect(currentTenant("org-0")).toBe("org-0");
    expect(currentTenant(() => tenant)).toBe("org-1");

    tenant = "org-2";

    expect(currentTenant(() => tenant)).toBe("org-2");
  });

  it("treats null, undefined and an empty id as no tenant", () => {
    expect(currentTenant(undefined)).toBeUndefined();
    expect(currentTenant("")).toBeUndefined();
    expect(currentTenant(() => null)).toBeUndefined();
    expect(currentTenant(() => undefined)).toBeUndefined();
  });
});

describe("requireOrganization", () => {
  it("returns the tenant", async () => {
    expect(await requireOrganization(() => "org-1")).toMatchObject({
      ok: true,
      data: "org-1",
    });
  });

  it("fails with TENANT_REQUIRED when there is none", async () => {
    const result = await requireOrganization(() => undefined);

    expect(result.ok).toBe(false);
    expect(result.ok ? undefined : result.error).toMatchObject({
      kind: "invalid_request",
      hint: "TENANT_REQUIRED",
    });
  });
});
