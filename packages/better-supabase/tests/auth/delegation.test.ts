import { describe, expect, it } from "vitest";

import {
  contextClaims,
  delegatedClaims,
  narrowCap,
  permissionCapOf,
  permissionMatches,
} from "../../src/auth/delegation.ts";

const user = { id: "user-1", kind: "user" as const };

describe("delegatedClaims", () => {
  it("is empty for a plain, support or impersonated session", () => {
    expect(delegatedClaims({})).toEqual({ ok: true });
    expect(delegatedClaims({ scope: "posts:read" })).toEqual({ ok: true });
    expect(
      delegatedClaims({
        act: { kind: "support", sub: "admin-1", session_id: "s-1" },
      }),
    ).toEqual({ ok: true });
    expect(
      delegatedClaims({ act: { kind: "impersonation", sub: "admin-1" } }),
    ).toEqual({ ok: true });
  });

  it("keeps the client, scopes, authorization details and the full act chain", () => {
    const act = { sub: "agent-1", act: { sub: "client-1", act: { sub: "x" } } };
    const details = [{ type: "payment_initiation", amount: 10 }];
    expect(
      delegatedClaims({
        client_id: "client-1",
        scope: "  posts:read   posts:write ",
        authorization_details: details,
        act,
      }),
    ).toEqual({
      ok: true,
      delegation: {
        client_id: "client-1",
        scope: "posts:read posts:write",
        authorization_details: details,
        act,
      },
    });
    expect(
      delegatedClaims({ client_id: "client-1", scope: ["a", "b"] }),
    ).toEqual({
      ok: true,
      delegation: { client_id: "client-1", scope: "a b" },
    });
    expect(delegatedClaims({ act: { sub: "client-1" } })).toEqual({
      ok: true,
      delegation: { act: { sub: "client-1" } },
    });
    expect(delegatedClaims({ client_id: "c", scope: "" })).toEqual({
      ok: true,
      delegation: { client_id: "c" },
    });
  });

  it("keeps client_id next to a support act, so SQL still narrows", () => {
    expect(
      delegatedClaims({
        client_id: "c",
        act: { kind: "support", sub: "admin-1", session_id: "s-1" },
      }),
    ).toEqual({ ok: true, delegation: { client_id: "c" } });
  });

  it("rejects an invalid act chain or malformed delegation claims", () => {
    for (const claims of [
      { act: { kind: "root", sub: "admin-1" } },
      { act: { sub: "a", act: { sub: "" } } },
      { act: "client-1" },
      { client_id: 7 },
      { client_id: "" },
      { client_id: "c", scope: 7 },
      { client_id: "c", scope: ["a", 1] },
      { client_id: "c", authorization_details: {} },
      { client_id: "c", authorization_details: [{ amount: 1 }] },
      { client_id: "c", authorization_details: [{ type: "" }] },
      { client_id: "c", authorization_details: ["x"] },
    ]) {
      expect({ claims, ok: delegatedClaims(claims).ok }).toEqual({
        claims,
        ok: false,
      });
    }
  });
});

describe("contextClaims", () => {
  it("runs as the user, in the tenant", () => {
    expect(contextClaims({ actor: user, tenant: "t1" })).toEqual({
      ok: true,
      claims: { role: "authenticated", sub: "user-1", tenant_id: "t1" },
    });
  });

  it("puts the delegation back into the claims and drops it from extra", () => {
    const built = contextClaims(
      {
        actor: user,
        claims: { client_id: "c", scope: "posts:read", email: "x@y.z" },
      },
      {
        extra: {
          scope: "posts:write",
          client_id: "other",
          authorization_details: [],
          act: { sub: "x" },
          user_role: "admin",
        },
      },
    );

    expect(built).toEqual({
      ok: true,
      claims: {
        user_role: "admin",
        role: "authenticated",
        sub: "user-1",
        client_id: "c",
        scope: "posts:read",
      },
    });
  });

  it("prefers a support act, then the client chain, then the impersonator", () => {
    const support = { kind: "support", sub: "admin-1", session_id: "s-1" };
    expect(
      contextClaims({
        actor: { ...user, impersonator: "admin-1" },
        claims: { act: support },
      }),
    ).toEqual({
      ok: true,
      claims: {
        role: "authenticated",
        sub: "user-1",
        act: { ...support, read_only: true },
      },
      impersonator: "admin-1",
      readOnly: true,
    });
    expect(
      contextClaims({
        actor: { ...user, impersonator: "admin-1" },
        claims: { act: { sub: "client-1" } },
      }),
    ).toEqual({
      ok: true,
      claims: {
        role: "authenticated",
        sub: "user-1",
        act: { sub: "client-1" },
      },
      impersonator: "admin-1",
    });
    expect(
      contextClaims(
        { actor: { ...user, impersonator: "admin-1" } },
        { reason: "replay" },
      ),
    ).toEqual({
      ok: true,
      claims: {
        role: "authenticated",
        sub: "user-1",
        act: { kind: "impersonation", sub: "admin-1", reason: "replay" },
      },
      impersonator: "admin-1",
    });
  });

  it("refuses a context without a user or with an invalid delegation", () => {
    expect(contextClaims({})).toEqual({
      ok: false,
      message:
        "forContext needs a user actor, got none: use admin() for service work",
    });
    expect(
      contextClaims({ actor: { id: "svc", kind: "service" } }),
    ).toMatchObject({ ok: false, message: expect.stringContaining("service") });
    expect(
      contextClaims({
        actor: user,
        claims: { act: { kind: "root", sub: "a" } },
      }),
    ).toEqual({ ok: false, message: "forContext got an invalid act claim" });
    expect(
      contextClaims({ actor: user, claims: { client_id: "c", scope: 1 } }),
    ).toEqual({
      ok: false,
      message: "forContext got invalid delegation claims",
    });
  });

  it("sets a permission cap that only ever narrows", () => {
    expect(
      contextClaims({ actor: user }, { permissions: ["posts.write"] }),
    ).toMatchObject({
      ok: true,
      claims: { bsb_permission_cap: ["posts.write"] },
    });
    expect(
      contextClaims(
        { actor: user, claims: { bsb_permission_cap: ["posts.*"] } },
        { permissions: ["posts.write", "billing.manage"] },
      ),
    ).toMatchObject({
      ok: true,
      claims: { bsb_permission_cap: ["posts.write"] },
    });
    expect(
      contextClaims({ actor: user, claims: { bsb_permission_cap: ["a"] } }),
    ).toMatchObject({ ok: true, claims: { bsb_permission_cap: ["a"] } });
    expect(
      contextClaims({ actor: user }, { extra: { bsb_permission_cap: ["*"] } }),
    ).toEqual({ ok: true, claims: { role: "authenticated", sub: "user-1" } });
    expect(
      contextClaims({ actor: user, claims: { bsb_permission_cap: "a" } }),
    ).toEqual({
      ok: false,
      message: "forContext got an invalid permission cap",
    });
  });

  it("carries a cap under its 0.14 name forward as bsb_permission_cap", () => {
    expect(
      contextClaims(
        { actor: user, claims: { bs_permission_cap: ["posts.*"] } },
        { permissions: ["posts.write", "billing.manage"] },
      ),
    ).toEqual({
      ok: true,
      claims: {
        role: "authenticated",
        sub: "user-1",
        bsb_permission_cap: ["posts.write"],
      },
    });
    expect(
      permissionCapOf({ bsb_permission_cap: ["a"], bs_permission_cap: ["b"] }),
    ).toEqual(["a"]);
    expect(
      contextClaims({ actor: user }, { extra: { bs_permission_cap: ["*"] } }),
    ).toEqual({ ok: true, claims: { role: "authenticated", sub: "user-1" } });
  });
});

describe("narrowCap and permissionMatches", () => {
  it("matches wildcards like permission_matches in SQL", () => {
    expect(permissionMatches("*", "x.y")).toBe(true);
    expect(permissionMatches("x.*", "x.y")).toBe(true);
    expect(permissionMatches("x.*", "xy")).toBe(false);
    expect(permissionMatches("x.y", "x.y")).toBe(true);
  });

  it("keeps either side alone and intersects both", () => {
    expect(narrowCap(undefined, undefined)).toBeUndefined();
    expect(narrowCap(["a"], undefined)).toEqual(["a"]);
    expect(narrowCap(undefined, ["b"])).toEqual(["b"]);
    expect(narrowCap(["a.*"], ["a.b", "c"])).toEqual(["a.b"]);
    expect(narrowCap([], ["a"])).toEqual([]);
  });
});
