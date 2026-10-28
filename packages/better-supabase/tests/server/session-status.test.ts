import { describe, expect, it, vi } from "vitest";

import type { AuthResolution, AuthState } from "../../src/auth/resolve.ts";
import type { SessionStatusServer } from "../../src/server/session-status.ts";
import type { ActiveSupport } from "../../src/server/support.ts";

import {
  claimsFingerprint,
  sessionStatusRoute,
} from "../../src/server/session-status.ts";

const user = (claims: Record<string, unknown> = {}): AuthState => ({
  kind: "user",
  token: "t",
  // SAFETY: the route reads plain claims; the JWT fields are not checked here.
  claims: { sub: "u1", role: "authenticated", exp: 100, iat: 1, ...claims },
  // SAFETY: only `id` is read.
  user: { id: "u1" },
  source: "cookie",
  expiresAt: 100,
});

function resolution(
  auth: AuthState,
  extra: Partial<AuthResolution> = {},
): AuthResolution {
  return {
    auth,
    cookies: [],
    headers: {},
    requestCookies: [],
    apply: (response) => {
      response.headers.append("set-cookie", "applied=1");

      return response;
    },
    ...extra,
  };
}

const support: ActiveSupport = {
  // SAFETY: the route reads id, targetUserId and readOnly.
  session: { id: "s1", targetUserId: "u2", readOnly: true } as never,
  admin: { id: "u1" },
  claims: { sub: "u2" },
};

function server(
  answer: AuthResolution,
  active?: ActiveSupport,
): SessionStatusServer & { calls: unknown[] } {
  const calls: unknown[] = [];

  return {
    calls,
    resolve: vi.fn(async (_request, options) => {
      calls.push(options);

      return answer;
    }),
    support: { current: async () => active },
  };
}

const get = (path = "/api/session-status") =>
  new Request(`https://app.test${path}`);

describe("sessionStatusRoute", () => {
  it("answers an active session with its fingerprint and cookies", async () => {
    const bs = server(resolution(user({ tenant_id: "o1" })));
    const response = await sessionStatusRoute(bs)(get());

    expect(response.status).toBe(200);
    expect(response.headers.get("cache-control")).toBe("no-store, private");
    expect(response.headers.get("set-cookie")).toBe("applied=1");
    expect(bs.calls).toEqual([{ verifySession: false, refresh: false }]);
    expect(await response.json()).toEqual({
      status: "active",
      userId: "u1",
      fingerprint: await claimsFingerprint({
        sub: "u1",
        role: "authenticated",
        tenant_id: "o1",
      }),
      expiresAt: 100,
      support: null,
    });
  });

  it("reports ended, banned, expired and signed-out callers", async () => {
    const ended = await sessionStatusRoute(
      server(
        resolution(
          { kind: "none", reason: "signed_out" },
          { sessionVerified: false, reason: "user_banned" },
        ),
      ),
    )(get());

    expect(await ended.json()).toMatchObject({
      status: "banned",
      fingerprint: null,
    });

    const expired = await sessionStatusRoute(
      server(resolution({ kind: "none", reason: "expired" })),
      { verifySession: false, refresh: true },
    )(get());

    expect(await expired.json()).toMatchObject({ status: "expired" });

    const none = await sessionStatusRoute(
      server(resolution({ kind: "none", reason: "none" })),
    )(get());

    expect(await none.json()).toMatchObject({
      status: "signed_out",
      userId: null,
    });
  });

  it("puts the support target in the fingerprint", async () => {
    const plain = await (
      await sessionStatusRoute(server(resolution(user())))(get())
    ).json();

    const viewing = await (
      await sessionStatusRoute(server(resolution(user()), support))(get())
    ).json();

    expect(viewing).toMatchObject({
      status: "active",
      support: { sessionId: "s1", targetUserId: "u2", readOnly: true },
    });
    expect(viewing.fingerprint).not.toBe(plain.fingerprint);
  });

  it("refuses other methods", async () => {
    const response = await sessionStatusRoute(server(resolution(user())))(
      new Request("https://app.test/x", { method: "POST" }),
    );

    expect(response.status).toBe(405);
  });
});

describe("claimsFingerprint", () => {
  it("ignores key order and the claims every refresh changes", async () => {
    expect(
      await claimsFingerprint({ a: 1, b: { y: 2, x: 1 }, exp: 1, iat: 2 }),
    ).toBe(await claimsFingerprint({ b: { x: 1, y: 2 }, a: 1, exp: 9 }));
    expect(await claimsFingerprint({ a: 1, role: "x" })).not.toBe(
      await claimsFingerprint({ a: 1, role: "y" }),
    );
    expect(
      await claimsFingerprint({ a: 1, aal: "aal2" }, undefined, ["aal"]),
    ).toBe(await claimsFingerprint({ a: 1 }));
  });
});

describe("sessionStatusRoute edges", () => {
  it("answers HEAD without a body and reads an ended session without a reason as ended", async () => {
    const head = await sessionStatusRoute(
      server(
        resolution(
          { kind: "none", reason: "none" },
          { sessionVerified: false, reason: "session_not_found" },
        ),
      ),
    )(new Request("https://app.test/api/session-status", { method: "HEAD" }));

    expect(head.status).toBe(200);
    expect(await head.text()).toBe("");

    const ended = await sessionStatusRoute(
      server(
        resolution(
          { kind: "none", reason: "none" },
          { sessionVerified: false, reason: "session_not_found" },
        ),
      ),
    )(get());

    expect(await ended.json()).toMatchObject({ status: "ended" });
  });
});

describe("claimsFingerprint values", () => {
  it("hashes arrays in order and treats undefined as absent or null", async () => {
    expect(await claimsFingerprint({ groups: ["a", "b"] })).not.toBe(
      await claimsFingerprint({ groups: ["b", "a"] }),
    );
    expect(await claimsFingerprint({ a: 1, gone: undefined })).toBe(
      await claimsFingerprint({ a: 1 }),
    );
    expect(await claimsFingerprint({ list: [undefined] })).toBe(
      await claimsFingerprint({ list: [null] }),
    );
  });
});
