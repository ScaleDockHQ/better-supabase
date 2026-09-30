import { describe, expect, it } from "vitest";

import type { AuthState } from "./resolve.ts";

import { actClaim, impersonatorOf } from "./impersonation.ts";
import { authContext } from "./resolve.ts";
import { toSession } from "./view.ts";

const act = actClaim({ actor: "admin-1", reason: "support ticket 42" });

function user(claims: Record<string, unknown>): AuthState {
  return {
    kind: "user",
    source: "header",
    token: "token",
    user: { id: "user-1", role: "authenticated" },
    claims: { sub: "user-1", ...claims },
    expiresAt: null,
  } as unknown as AuthState;
}

describe("impersonation", () => {
  it("reads the act claim, ignoring malformed ones", () => {
    expect(act).toEqual({ sub: "admin-1", reason: "support ticket 42" });
    expect(impersonatorOf({ act })).toEqual({
      id: "admin-1",
      reason: "support ticket 42",
    });
    expect(impersonatorOf({ act: { sub: "admin-1" } })).toEqual({
      id: "admin-1",
    });
    expect(impersonatorOf({ act: "admin-1" })).toBeUndefined();
    expect(impersonatorOf({ act: { sub: "" } })).toBeUndefined();
    expect(impersonatorOf({})).toBeUndefined();
  });

  it("sets session.impersonator and the actor only when acting", () => {
    const acting = toSession(user({ act }));
    expect(acting).toMatchObject({
      kind: "user",
      impersonator: { id: "admin-1", reason: "support ticket 42" },
    });
    expect(toSession(user({}))).not.toHaveProperty("impersonator");
    expect(authContext(user({ act })).actor).toMatchObject({
      id: "user-1",
      impersonator: "admin-1",
    });
    expect(authContext(user({})).actor).not.toHaveProperty("impersonator");
  });
});
