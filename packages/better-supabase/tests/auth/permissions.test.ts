import { describe, expect, it } from "vitest";

import type { AuthSession } from "../../src/auth/view.ts";
import type { AuthSnapshot } from "../../src/client/bind.ts";

import { permissionsOf } from "../../src/auth/permissions.ts";

function session(claims: Record<string, unknown>): AuthSession {
  return { kind: "user", claims } as unknown as AuthSession;
}

const claims = {
  sub: "u1",
  tenant_id: "org-1",
  permissions: { "org-1": ["projects.read", "projects.write"], "org-2": [] },
};

describe("permissionsOf", () => {
  it("reads the keys of the active tenant, or the tenant passed", () => {
    expect(permissionsOf(session(claims))).toEqual([
      "projects.read",
      "projects.write",
    ]);
    expect(permissionsOf(session(claims), "org-2")).toEqual([]);
  });

  it("is undefined when the token can't answer", () => {
    expect(permissionsOf(session(claims), "org-3")).toBeUndefined();
    expect(permissionsOf(session({ sub: "u1" }))).toBeUndefined();
    expect(
      permissionsOf(session({ ...claims, permissions_truncated: true })),
    ).toBeUndefined();
    expect(
      permissionsOf(session({ ...claims, permissions: { "org-1": [1] } })),
    ).toBeUndefined();
    expect(permissionsOf({ kind: "none", reason: "none" })).toBeUndefined();
  });

  it("reads a renamed claim and a client snapshot", () => {
    const snapshot = {
      status: "signed-in",
      user: { id: "u1" },
      claims: { org: "org-9", perms: { "org-9": ["a"] } },
    } as unknown as AuthSnapshot;

    expect(
      permissionsOf(snapshot, undefined, {
        claim: "perms",
        tenantClaim: "org",
      }),
    ).toEqual(["a"]);
    expect(
      permissionsOf({ status: "signed-out", user: null, claims: null }),
    ).toBeUndefined();
  });
});
