import { describe, expect, it } from "vitest";

import type { AuthSession } from "../../src/auth/view.ts";
import type { AuthSnapshot } from "../../src/client/bind.ts";

import { tenantOf } from "../../src/auth/tenant.ts";

const claims = { sub: "u1", app_metadata: { tenant_id: "org-1" } };

describe("tenantOf", () => {
  it("reads the tenant of a server user session", () => {
    const session = { kind: "user", claims } as unknown as AuthSession;
    expect(tenantOf(session)).toBe("org-1");
    const anon = { kind: "anon", reason: "no-token" } as unknown as AuthSession;
    expect(tenantOf(anon)).toBeUndefined();
  });

  it("reads the tenant of a client auth snapshot", () => {
    const signedIn = {
      status: "signed-in",
      user: { id: "u1" },
      claims: { org: "org-2", ...claims },
    } as unknown as AuthSnapshot;
    expect(tenantOf(signedIn)).toBe("org-1");
    expect(tenantOf(signedIn, "org")).toBe("org-2");
    expect(
      tenantOf({ status: "signed-out", user: null, claims: null }),
    ).toBeUndefined();
  });
});
