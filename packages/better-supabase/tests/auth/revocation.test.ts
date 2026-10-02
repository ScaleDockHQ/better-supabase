import { describe, expect, it } from "vitest";

import { checkSession, type SessionLookup } from "../../src/auth/revocation.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const SESSION = "22222222-2222-4222-8222-222222222222";

function lookup(active: boolean | undefined) {
  const calls: unknown[][] = [];
  const sql: SessionLookup = {
    queryRaw: <T>(text: string, params?: unknown[]) => {
      calls.push([text, params]);
      return Promise.resolve((active === undefined ? [] : [{ active }]) as T[]);
    },
  };
  return { sql, calls };
}

const user = (claims: Record<string, unknown>) => ({
  kind: "user" as const,
  claims,
});

describe("checkSession", () => {
  it("passes a user whose session still exists", async () => {
    const { sql, calls } = lookup(true);
    expect(
      await checkSession(sql, user({ sub: USER, session_id: SESSION })),
    ).toBeUndefined();
    expect(calls[0]?.[1]).toEqual([SESSION, USER]);
    expect(String(calls[0]?.[0])).toContain("from auth.sessions");
  });

  it.each([
    ["an ended session", lookup(false)],
    ["no row", lookup(undefined)],
  ])("rejects %s with SESSION_REVOKED", async (_name, { sql }) => {
    expect(
      await checkSession(sql, user({ sub: USER, session_id: SESSION })),
    ).toMatchObject({ kind: "unauthorized", code: "SESSION_REVOKED" });
  });

  it.each([
    ["no session_id", { sub: USER }],
    ["a malformed session_id", { sub: USER, session_id: "x" }],
    ["a malformed sub", { sub: "x", session_id: SESSION }],
  ])("rejects a token with %s without a query", async (_name, claims) => {
    const { sql, calls } = lookup(true);
    expect(await checkSession(sql, user(claims))).toMatchObject({
      code: "SESSION_REVOKED",
    });
    expect(calls).toHaveLength(0);
  });

  it("leaves non-user callers to guard", async () => {
    const { sql, calls } = lookup(false);
    expect(await checkSession(sql, { kind: "service" })).toBeUndefined();
    expect(await checkSession(sql, { kind: "anon" })).toBeUndefined();
    expect(calls).toHaveLength(0);
  });
});
