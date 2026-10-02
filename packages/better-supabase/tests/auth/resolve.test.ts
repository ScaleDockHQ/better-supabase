import type { StandardSchemaV1 } from "@standard-schema/spec";

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  authContext,
  clearVerifiedTokens,
  resolveAuth,
  type ResolveAuthOptions,
} from "../../src/auth/resolve.ts";
import { type StoredSession, writeSession } from "../../src/auth/session.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const NAME = "sb-abcdefghijklmnopqrst-auth-token";
const USER = "11111111-1111-4111-8111-111111111111";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const signer = await createTestSigner();

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

/** A local JWKS object; the memo is keyed by its identity. */
function keys(): { keys: JsonWebKey[] } {
  return { keys: [...signer.jwks.keys] };
}

function bearer(token: string): Request {
  return new Request("https://api.test/", {
    headers: { authorization: `Bearer ${token}` },
  });
}

function cookieRequest(cookie: string): Request {
  return new Request("https://app.test/", { headers: { cookie } });
}

function sessionCookie(session: StoredSession): string {
  return writeSession([], NAME, session)
    .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
    .join("; ");
}

function schema<T>(
  validate: (
    value: unknown,
  ) => StandardSchemaV1.Result<T> | Promise<StandardSchemaV1.Result<T>>,
): StandardSchemaV1<unknown, T> {
  return { "~standard": { version: 1, vendor: "test", validate } };
}

const exp = (token: string): number =>
  JSON.parse(atob(token.split(".")[1]!.replace(/-/g, "+").replace(/_/g, "/")))
    .exp as number;

describe("verified token memo", () => {
  it("reuses a verified token until it expires", async () => {
    const jwks = keys();
    const options: ResolveAuthOptions = { env, jwks };
    const token = await signer.sign({ sub: USER });
    expect((await resolveAuth(bearer(token), options)).auth.kind).toBe("user");

    // With the keys gone only a memo hit still verifies.
    jwks.keys.length = 0;
    expect((await resolveAuth(bearer(token), options)).auth.kind).toBe("user");
    const later = { ...options, now: () => (exp(token) + 1) * 1000 };
    expect((await resolveAuth(bearer(token), later)).auth).toMatchObject({
      kind: "invalid",
      reason: "token",
    });
  });

  it("forgets every token on clearVerifiedTokens", async () => {
    const jwks = keys();
    const options: ResolveAuthOptions = { env, jwks };
    const token = await signer.sign({ sub: USER });
    await resolveAuth(bearer(token), options);
    jwks.keys.length = 0;
    clearVerifiedTokens();
    expect((await resolveAuth(bearer(token), options)).auth.kind).toBe(
      "invalid",
    );
  });

  it("evicts the oldest token past 256 entries", async () => {
    const jwks = keys();
    const options: ResolveAuthOptions = { env, jwks };
    const tokens = await Promise.all(
      Array.from({ length: 257 }, (_, index) =>
        signer.sign({ sub: USER, n: index }),
      ),
    );
    for (const token of tokens) await resolveAuth(bearer(token), options);
    jwks.keys.length = 0;
    expect((await resolveAuth(bearer(tokens[0]!), options)).auth.kind).toBe(
      "invalid",
    );
    expect((await resolveAuth(bearer(tokens[256]!), options)).auth.kind).toBe(
      "user",
    );
  });

  it("never remembers a token without exp", async () => {
    const jwks = keys();
    const options: ResolveAuthOptions = { env, jwks };
    const token = await signer.sign({ sub: USER, exp: undefined });
    const first = await resolveAuth(bearer(token), options);
    expect(first.auth).toMatchObject({ kind: "user", expiresAt: null });
    jwks.keys.length = 0;
    expect((await resolveAuth(bearer(token), options)).auth.kind).toBe(
      "invalid",
    );
  });

  it("fetches a remote JWKS, keyed by URL, audience and issuer", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(async () =>
      Response.json(signer.jwks),
    );
    vi.stubGlobal("fetch", fetch);
    const jwksUrl = new URL(`${PROJECT_URL}/remote-a/jwks.json`);
    const options: ResolveAuthOptions = {
      env: { ...env, jwksUrl },
      audience: "authenticated",
      issuer: ["https://issuer.test"],
    };
    const token = await signer.sign({
      sub: USER,
      iss: "https://issuer.test",
    });
    expect((await resolveAuth(bearer(token), options)).auth).toMatchObject({
      kind: "user",
      user: { id: USER },
    });
    expect(String(fetch.mock.calls[0]![0])).toBe(String(jwksUrl));
    const wrongIssuer = await signer.sign({ sub: USER, iss: "https://x.test" });
    expect((await resolveAuth(bearer(wrongIssuer), options)).auth.kind).toBe(
      "invalid",
    );
  });

  it("maps an unreachable JWKS to a network error and keeps the cookie session", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("down", { status: 500 })),
    );
    const options: ResolveAuthOptions = {
      env: { ...env, jwksUrl: new URL(`${PROJECT_URL}/remote-b/jwks.json`) },
      refresh: true,
      fetch: vi.fn<typeof globalThis.fetch>(),
    };
    const token = await signer.sign({ sub: USER });
    const { auth } = await resolveAuth(bearer(token), options);
    expect(auth).toMatchObject({
      kind: "invalid",
      reason: "token",
      error: { kind: "network", code: "JWKS_FETCH_FAILED" },
    });

    const session = await resolveAuth(
      cookieRequest(
        sessionCookie({
          access_token: token,
          refresh_token: "r-network",
          expires_at: exp(token),
          token_type: "bearer",
          user: { id: USER },
        }),
      ),
      options,
    );
    expect(session.auth).toMatchObject({ error: { kind: "network" } });
    expect(options.fetch).not.toHaveBeenCalled();
  });
});

describe("cookie sessions", () => {
  const options: ResolveAuthOptions = { env, jwks: signer.jwks as never };

  it("reads the expiry from the access token when expires_at is missing", async () => {
    const token = await signer.sign({ sub: USER });
    const { auth } = await resolveAuth(
      cookieRequest(
        sessionCookie({
          access_token: token,
          refresh_token: "r",
          token_type: "bearer",
          user: { id: USER },
        }),
      ),
      options,
    );
    expect(auth).toMatchObject({ kind: "user", source: "cookie" });
  });

  it("treats undecodable access tokens as expired", async () => {
    for (const access_token of [
      "opaque",
      "a.!!!.c",
      `a.${btoa("5")}.c`,
      `a.${btoa(JSON.stringify({ exp: "soon" }))}.c`,
    ]) {
      const { auth } = await resolveAuth(
        cookieRequest(
          sessionCookie({
            access_token,
            refresh_token: "r",
            token_type: "bearer",
            user: { id: USER },
          }),
        ),
        options,
      );
      expect(auth).toEqual({ kind: "anon", reason: "expired" });
    }
  });

  it("signs out a fresh session whose token fails, refreshing only when allowed", async () => {
    const other = await createTestSigner();
    const token = await other.sign({ sub: USER });
    const cookie = sessionCookie({
      access_token: token,
      refresh_token: "r-foreign",
      expires_at: exp(token),
      token_type: "bearer",
      user: { id: USER },
    });
    expect((await resolveAuth(cookieRequest(cookie), options)).auth).toEqual({
      kind: "anon",
      reason: "signed_out",
    });

    const fresh = await signer.sign({ sub: USER });
    const fetch = vi.fn<typeof globalThis.fetch>(async () =>
      Response.json({
        access_token: fresh,
        refresh_token: "r-next",
        expires_in: 3600,
        token_type: "bearer",
        user: { id: USER },
      }),
    );
    const refreshed = await resolveAuth(cookieRequest(cookie), {
      ...options,
      refresh: true,
      fetch,
      now: () => Date.now(),
    });
    expect(fetch).toHaveBeenCalledTimes(1);
    expect(refreshed.auth).toMatchObject({ kind: "user", token: fresh });
    expect(refreshed.cookies.length).toBeGreaterThan(0);
  });

  it("clears a stale cookie it can't read only where it can write", async () => {
    const stale = cookieRequest(`${NAME}=garbage; other=1`);
    const read = await resolveAuth(stale, options);
    expect(read.auth).toEqual({ kind: "anon", reason: "signed_out" });
    expect(read.cookies).toEqual([]);

    const cleared = await resolveAuth(cookieRequest(`${NAME}.0=garbage`), {
      ...options,
      refresh: true,
    });
    expect(cleared.auth).toEqual({ kind: "anon", reason: "signed_out" });
    expect(cleared.cookies.map((write) => write.name)).toContain(`${NAME}.0`);
    expect(cleared.cookies.every((write) => write.options.maxAge === 0)).toBe(
      true,
    );
    expect(cleared.headers["Cache-Control"]).toContain("no-store");
  });

  it("uses a custom cookie name", async () => {
    const token = await signer.sign({ sub: USER });
    const writes = writeSession([], "session", {
      access_token: token,
      refresh_token: "r",
      expires_at: exp(token),
      token_type: "bearer",
      user: { id: USER },
    });
    const { auth } = await resolveAuth(
      cookieRequest(
        writes
          .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
          .join("; "),
      ),
      { ...options, cookie: { name: "session" } },
    );
    expect(auth).toMatchObject({ kind: "user", source: "cookie" });
  });

  it("copies the response when its headers are immutable", async () => {
    const response = await resolveAuth(cookieRequest(`${NAME}=garbage`), {
      ...options,
      refresh: true,
    });
    const redirect = Response.redirect("https://app.test/login", 302);
    const applied = response.apply(redirect);
    expect(applied).not.toBe(redirect);
    expect(applied.status).toBe(302);
    expect(applied.headers.get("location")).toBe("https://app.test/login");
    expect(applied.headers.getSetCookie()[0]).toMatch(new RegExp(`^${NAME}=`));
    expect(applied.headers.get("cache-control")).toContain("no-store");

    const untouched = new Response("ok");
    expect((await resolveAuth(bearer("x"), options)).apply(untouched)).toBe(
      untouched,
    );
  });
});

describe("claims and user_metadata schemas", () => {
  const options: ResolveAuthOptions = { env, jwks: signer.jwks as never };

  it("joins issues without a path and with numeric paths", async () => {
    const token = await signer.sign({ sub: USER });
    const { auth } = await resolveAuth(bearer(token), {
      ...options,
      claims: schema(() => ({
        issues: [
          { message: "bad token" },
          { message: "bad role", path: ["roles", 0] },
        ],
      })),
    });
    expect(auth).toMatchObject({
      kind: "invalid",
      reason: "claims",
      error: {
        message: "The token claims are invalid (bad token; roles.0: bad role)",
      },
    });
  });

  it("keeps the claims when an async schema returns a non-object", async () => {
    const token = await signer.sign({ sub: USER, tenant_id: "t1" });
    const { auth } = await resolveAuth(bearer(token), {
      ...options,
      claims: schema(async () => ({ value: "ok" })),
    });
    expect(auth).toMatchObject({
      kind: "user",
      claims: { sub: USER, tenant_id: "t1" },
    });
  });

  it("rejects a malformed act claim", async () => {
    const token = await signer.sign({ sub: USER, act: { reason: "no sub" } });
    const { auth } = await resolveAuth(bearer(token), options);
    expect(auth).toMatchObject({
      kind: "invalid",
      reason: "actor",
      error: { code: "ACTOR_INVALID" },
    });
  });

  it("runs async user_metadata schemas and warns through console by default", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const token = await signer.sign({
      sub: USER,
      user_metadata: { theme: "dark" },
    });
    const parsed = await resolveAuth(bearer(token), {
      ...options,
      userMetadata: schema(async (value) => ({ value })),
    });
    expect(parsed.auth).toMatchObject({ profile: { theme: "dark" } });

    const failing = await resolveAuth(bearer(token), {
      ...options,
      userMetadata: schema(() => ({
        issues: [
          { message: "no path" },
          { message: "index", path: [0, { key: "theme" }] },
        ],
      })),
    });
    expect(failing.auth).not.toHaveProperty("profile");
    expect(warn).toHaveBeenCalledTimes(1);
    expect(JSON.stringify(warn.mock.calls[0])).toContain('["","0.theme"]');
  });
});

describe("authContext", () => {
  it("carries role, email and the impersonator for users", () => {
    expect(
      authContext({
        kind: "user",
        token: "t",
        claims: {
          sub: USER,
          role: "authenticated",
          act: { sub: "admin-1" },
        },
        user: { id: USER, role: "authenticated", email: "a@b.c" },
        source: "bearer",
        expiresAt: null,
      }),
    ).toEqual({
      actor: {
        id: USER,
        kind: "user",
        role: "authenticated",
        email: "a@b.c",
        impersonator: "admin-1",
      },
      claims: { sub: USER, role: "authenticated", act: { sub: "admin-1" } },
    });
    expect(
      authContext({
        kind: "user",
        token: "t",
        claims: { sub: USER },
        user: { id: USER },
        source: "bearer",
        expiresAt: null,
      }).actor,
    ).toEqual({ id: USER, kind: "user" });
  });

  it("maps service, anon and invalid callers", () => {
    expect(authContext({ kind: "service", keyName: "cron" })).toEqual({
      actor: { id: "service:cron", kind: "service", role: "service_role" },
      claims: { role: "service_role" },
    });
    const anon = {
      actor: { id: "anon", kind: "anon", role: "anon" },
      claims: { role: "anon" },
    };
    expect(authContext({ kind: "anon", reason: "none" })).toEqual(anon);
    expect(
      authContext({
        kind: "invalid",
        reason: "token",
        error: { kind: "unauthorized", message: "x", status: 401 } as never,
      }),
    ).toEqual(anon);
  });
});
