import { describe, expect, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";

import { actClaim, impersonatorOf } from "../../src/auth/impersonation.ts";
import { authContext } from "../../src/auth/resolve.ts";
import { toSession } from "../../src/auth/view.ts";

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
    expect(act).toEqual({
      kind: "impersonation",
      sub: "admin-1",
      reason: "support ticket 42",
    });
    expect(impersonatorOf({ act })).toEqual({
      kind: "impersonation",
      id: "admin-1",
      reason: "support ticket 42",
    });
    expect(
      impersonatorOf({ act: { kind: "impersonation", sub: "admin-1" } }),
    ).toEqual({ kind: "impersonation", id: "admin-1" });
    // An unmarked act is an OAuth client or agent chain, not an admin.
    expect(impersonatorOf({ act: { sub: "admin-1" } })).toBeUndefined();
    expect(impersonatorOf({ client_id: "app" })).toBeUndefined();
    expect(
      impersonatorOf({ act: { kind: "auditor", sub: "admin-1" } }),
    ).toBeUndefined();
    expect(impersonatorOf({ act: "admin-1" })).toBeUndefined();
    expect(impersonatorOf({ act: { sub: "" } })).toBeUndefined();
    expect(impersonatorOf({})).toBeUndefined();
  });

  it("sets session.impersonator and the actor only when acting", () => {
    const acting = toSession(user({ act }));
    expect(acting).toMatchObject({
      kind: "user",
      impersonator: {
        kind: "impersonation",
        id: "admin-1",
        reason: "support ticket 42",
      },
      actor: { kind: "impersonation", id: "admin-1" },
    });
    expect(toSession(user({}))).not.toHaveProperty("impersonator");
    expect(authContext(user({ act })).actor).toMatchObject({
      id: "user-1",
      impersonator: "admin-1",
    });
    expect(authContext(user({})).actor).not.toHaveProperty("impersonator");
  });
});
