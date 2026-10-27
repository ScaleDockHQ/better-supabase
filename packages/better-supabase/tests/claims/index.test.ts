import { describe, expect, it } from "vitest";

import type { AuthSession } from "../../src/auth/view.ts";

import {
  AUTHZ_VERSION_CLAIM,
  decodeEntitlementClaim,
  FEATURES_CLAIM,
  isApiKeySession,
  isTruncated,
  isUserSession,
  MEMBERSHIPS_CLAIM,
  PERMISSION_CAP_CLAIM,
  permissionCapOf,
  permissionsOf,
  PERMISSIONS_CLAIM,
  PERMISSIONS_TRUNCATED_CLAIM,
  tenantOf,
} from "../../src/claims/index.ts";
import { DEFAULT_CLAIMS } from "../../src/core/claims.ts";

const claims = {
  sub: "u1",
  tenant_id: "org-1",
  permissions: { "org-1": ["projects.read"], "org-2": [] },
  features: { "org-1": ["a", "sso"], "org-2": "bad" },
};

describe("claim names", () => {
  it("match the names the hook and the runtime defaults write", () => {
    expect(PERMISSION_CAP_CLAIM).toBe("bsb_permission_cap");
    expect(AUTHZ_VERSION_CLAIM).toBe("authz_ver");
    expect(MEMBERSHIPS_CLAIM).toBe(DEFAULT_CLAIMS.memberships);
    expect(FEATURES_CLAIM).toBe(DEFAULT_CLAIMS.features);
    expect(PERMISSIONS_CLAIM).toBe(DEFAULT_CLAIMS.permissions);
    expect(PERMISSIONS_TRUNCATED_CLAIM).toBe(`${PERMISSIONS_CLAIM}_truncated`);
  });
});

describe("permissionsOf on plain claims", () => {
  it("reads verified claims without a session", () => {
    expect(permissionsOf(claims)).toEqual(["projects.read"]);
    expect(permissionsOf(claims, "org-2")).toEqual([]);
    expect(tenantOf(claims)).toBe("org-1");
  });

  it("honors a provider's own truncated marker", () => {
    const marked = { ...claims, perms_partial: true };

    expect(permissionsOf(marked)).toEqual(["projects.read"]);
    expect(
      permissionsOf(marked, undefined, { truncatedClaim: "perms_partial" }),
    ).toBeUndefined();
  });
});

describe("isTruncated", () => {
  it("reads the default marker, a renamed claim and a declared marker", () => {
    expect(isTruncated({ permissions_truncated: true })).toBe(true);
    expect(isTruncated({ permissions_truncated: "yes" })).toBe(false);
    expect(isTruncated({ grants_truncated: true }, "grants")).toBe(true);
    expect(
      isTruncated({ partial: true }, "permissions", { marker: "partial" }),
    ).toBe(true);
    expect(isTruncated({})).toBe(false);
  });
});

describe("decodeEntitlementClaim", () => {
  it("turns short codes back into feature keys per tenant", () => {
    expect(
      decodeEntitlementClaim(claims, { keys: { "api.access": "a" } }),
    ).toEqual({ "org-1": ["api.access", "sso"] });
  });

  it("is empty without a features claim", () => {
    expect(decodeEntitlementClaim({ sub: "u1" })).toEqual({});
    expect(decodeEntitlementClaim({ kind: "none", reason: "none" })).toEqual(
      {},
    );
  });
});

describe("permissionCapOf", () => {
  it("reads the cap, and false for a malformed one", () => {
    expect(permissionCapOf({ bsb_permission_cap: ["a.read"] })).toEqual([
      "a.read",
    ]);
    expect(permissionCapOf({ bsb_permission_cap: "a.read" })).toBe(false);
    expect(permissionCapOf({})).toBeUndefined();
  });
});

describe("session guards", () => {
  it("narrow user and API key sessions", () => {
    const apiKey: AuthSession = {
      kind: "apiKey",
      keyId: "k1",
      name: "ci",
      scopes: ["read"],
    };

    const none: AuthSession = { kind: "none", reason: "none" };

    expect(isApiKeySession(apiKey)).toBe(true);
    expect(isUserSession(apiKey)).toBe(false);
    expect(isApiKeySession(none)).toBe(false);
    expect(
      [apiKey].filter(isApiKeySession).map((session) => session.keyId),
    ).toEqual(["k1"]);
  });
});
