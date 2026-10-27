import { describe, expect, it } from "vitest";

import { isSessionSnapshot } from "../../src/claims/index.ts";
import {
  authorizationRequest,
  sessionSnapshot,
} from "../../src/testing/index.ts";

const user = "00000000-0000-4000-8000-000000000001";

describe("authorizationRequest", () => {
  it("builds the subject and context the server sends", () => {
    const request = authorizationRequest({
      action: "documents.read",
      claims: { sub: user, role: "authenticated", aal: "aal2", scope: "a b" },
      resource: { type: "documents", id: "d1", source: "loaded" },
      context: {
        tenant: "org-1",
        intent: "read",
        operation: "get",
        requestId: "r1",
        approval: "ap1",
      },
    });

    expect(request.subject).toMatchObject({
      type: "user",
      id: user,
      properties: { role: "authenticated", claims: { sub: user } },
    });
    expect(Object.isFrozen(request.subject.properties?.["claims"])).toBe(true);
    expect(request.context).toEqual({
      tenant: "org-1",
      aal: "aal2",
      scopes: ["a", "b"],
      intent: "read",
      operation: "get",
      requestId: "r1",
      approval: "ap1",
    });
    expect(request.resource).toEqual({
      type: "documents",
      id: "d1",
      source: "loaded",
    });
  });

  it("is anonymous without claims or a subject", () => {
    const request = authorizationRequest({ action: "documents.read" });

    expect(request.subject).toEqual({ type: "anon", id: "anonymous" });
    expect(request.resource).toEqual({ type: "test" });
  });
});

describe("sessionSnapshot", () => {
  it("builds a branded snapshot from the claims", () => {
    const snapshot = sessionSnapshot({
      claims: { sub: user, exp: 2_000_000_000, iat: 1_900_000_000 },
    });

    expect(isSessionSnapshot(snapshot)).toBe(true);
    expect(snapshot.userId).toBe(user);
    expect(snapshot.expiresAt).toBe(2_000_000_000);
    expect(snapshot.issuedAt).toBe(1_900_000_000);
    expect(snapshot.accessToken.split(".")).toHaveLength(3);
  });

  it("refuses claims without sub", () => {
    expect(() => sessionSnapshot({ claims: {} })).toThrow("claims.sub");
  });
});
