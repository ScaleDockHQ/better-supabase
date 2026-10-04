import { describe, expect, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";

import { toSession } from "../../src/auth/view.ts";
import { guard, respond } from "../../src/server/respond.ts";
import { supabaseClaimFixtures } from "../../src/testing/index.ts";

function user(claims: Record<string, unknown>): AuthState {
  return {
    kind: "user",
    source: "bearer",
    token: "token",
    user: { id: "u1", role: "authenticated" },
    claims: { sub: "u1", ...claims },
    expiresAt: null,
  } as unknown as AuthState;
}

describe("guard and anonymous users", () => {
  const anonymous = user({ is_anonymous: true });

  it("refuses anonymous users by default", () => {
    expect(guard(anonymous)).toMatchObject({
      kind: "forbidden",
      code: "ANONYMOUS_USER",
    });
    expect(guard(anonymous, ["user", "service"])).toMatchObject({
      code: "ANONYMOUS_USER",
    });
  });

  it("admits them only when allow lists anonymous", () => {
    expect(guard(anonymous, ["user", "anonymous"])).toBeUndefined();
    expect(guard(anonymous, ["anonymous"])).toBeUndefined();
    expect(guard(anonymous, ["user", "anon"])).toMatchObject({
      code: "ANONYMOUS_USER",
    });
    expect(guard(anonymous, ["anon"])).toMatchObject({
      code: "ANONYMOUS_USER",
    });
  });

  it("keeps anonymous apart from full users and from no session", () => {
    const full = user({});
    const none = { kind: "anon", reason: "none" } as unknown as AuthState;
    expect(guard(full, ["anonymous"])).toMatchObject({ kind: "forbidden" });
    expect(guard(full, ["user", "anonymous"])).toBeUndefined();
    expect(guard(none, ["anonymous"])).toMatchObject({
      code: "MISSING_CREDENTIALS",
    });
    expect(guard(none, ["user", "anon"])).toBeUndefined();
  });

  it("lets permanent users through", () => {
    expect(guard(user({ is_anonymous: false }))).toBeUndefined();
    expect(guard(user({}))).toBeUndefined();
  });

  it("marks the session", () => {
    expect(toSession(anonymous)).toMatchObject({ anonymous: true });
    expect(toSession(user({}))).toMatchObject({ anonymous: false });
  });
});

describe("guard and delegated scopes", () => {
  const as = (name: keyof typeof supabaseClaimFixtures) =>
    user(supabaseClaimFixtures[name].claims);

  it("limits only an oauth-client actor to the delegated scopes", () => {
    expect(guard(as("oauthClient"), ["user"], "aal1", ["posts:read"])).toBe(
      undefined,
    );
    expect(
      guard(as("agentChain"), ["user"], "aal1", ["posts:write"]),
    ).toMatchObject({ code: "INSUFFICIENT_SCOPE" });
  });

  it("checks support and impersonated sessions as the user's own", () => {
    for (const name of [
      "supportSession",
      "supportSessionReadOnly",
      "impersonation",
    ] as const) {
      expect(guard(as(name), ["user"], "aal1", ["posts:write"])).toBe(
        undefined,
      );
    }
  });
});

describe("respond", () => {
  it("writes bigints as decimal strings", async () => {
    const response = await respond(() => ({
      id: 9007199254740993n,
      ids: [1n],
    }));
    expect(response.headers.get("content-type")).toBe("application/json");
    expect(await response.text()).toBe('{"id":"9007199254740993","ids":["1"]}');
  });
});
