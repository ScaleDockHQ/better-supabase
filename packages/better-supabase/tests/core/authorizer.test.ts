import { describe, expect, it } from "vitest";

import { requestOf } from "../../src/core/authorizer.ts";

const USER = "11111111-1111-4111-8111-111111111111";

const claims = {
  aal: "aal2",
  memberships: [{ tenant: "o1", role: "owner" }],
  roles: ["admin"],
};

describe("requestOf claims", () => {
  it("passes the verified claims of a user actor", () => {
    const { subject } = requestOf({
      actor: { id: USER, kind: "user", role: "authenticated" },
      claims,
    });
    expect(subject.type).toBe("user");
    expect(subject.properties).toEqual({ role: "authenticated", claims });
  });

  it("passes the claims, including act, to an agent", () => {
    const delegated = { ...claims, act: { sub: "agent-1" } };
    const { subject } = requestOf({
      actor: { id: USER, kind: "user" },
      claims: delegated,
    });
    expect(subject.type).toBe("agent");
    expect(subject.properties?.["claims"]).toEqual(delegated);
  });

  it("gives an anonymous caller no claims", () => {
    expect(requestOf(undefined).subject).toEqual({
      type: "anon",
      id: "anonymous",
    });
    expect(requestOf({ claims }).subject).toEqual({
      type: "anon",
      id: "anonymous",
    });
  });

  it("leaves out claims that are not an object", () => {
    const { subject } = requestOf({
      actor: { id: USER, kind: "user" },
    });
    expect(subject.properties).toEqual({});
  });

  it("returns a read-only copy", () => {
    const context = { actor: { id: USER, kind: "user" as const }, claims };
    const copy = requestOf(context).subject.properties?.["claims"] as Record<
      string,
      unknown
    >;
    expect(copy).not.toBe(claims);
    expect(() => {
      copy["roles"] = ["owner"];
    }).toThrow(TypeError);
    const memberships = copy["memberships"] as Record<string, unknown>[];
    expect(() => {
      memberships[0]!["role"] = "guest";
    }).toThrow(TypeError);
    expect(context.claims).toEqual({
      aal: "aal2",
      memberships: [{ tenant: "o1", role: "owner" }],
      roles: ["admin"],
    });
  });
});
