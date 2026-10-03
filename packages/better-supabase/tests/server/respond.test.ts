import { describe, expect, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";

import { toSession } from "../../src/auth/view.ts";
import { guard, respond } from "../../src/server/respond.ts";

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

  it("admits them when allow lists anonymous or anon", () => {
    expect(guard(anonymous, ["user", "anonymous"])).toBeUndefined();
    expect(guard(anonymous, ["user", "anon"])).toBeUndefined();
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
