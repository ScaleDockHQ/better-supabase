import { describe, expect, test, vi } from "vitest";

import {
  authorizeUrl,
  exchangeCode,
  isFlow,
  needsRefresh,
  OAuthError,
  pkcePair,
  refreshSession,
  returnPath,
  seal,
  isSession,
  unseal,
  withDeployFlag,
} from "../../../src/create/supabase/index.ts";

const SECRET = "a-cookie-secret-of-at-least-32-characters";

const config = {
  clientId: "client",
  clientSecret: "secret",
  cookieSecret: SECRET,
};

function tokenFetch(body: Record<string, string | number>, status = 200) {
  return vi.fn<typeof fetch>(() =>
    Promise.resolve(Response.json(body, { status })),
  );
}

describe("pkcePair", () => {
  test("the challenge is the base64url SHA-256 of the verifier", async () => {
    const { verifier, challenge } = await pkcePair();

    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(verifier),
    );

    const expected = btoa(String.fromCodePoint(...new Uint8Array(digest)))
      .replaceAll("+", "-")
      .replaceAll("/", "_")
      .replace(/=+$/u, "");

    expect(challenge).toBe(expected);
    expect(verifier).toMatch(/^[\w-]{43,}$/u);
  });
});

describe("seal", () => {
  const session = { accessToken: "token", expiresAt: 1000 };

  test("round-trips a value", async () => {
    const sealed = await seal(session, SECRET);

    expect(sealed).not.toContain("token");
    await expect(unseal(sealed, SECRET, isSession)).resolves.toEqual(session);
  });

  test("rejects a tampered value, another secret or another shape", async () => {
    const sealed = await seal(session, SECRET);
    const tampered = `${sealed.slice(0, -2)}${sealed.endsWith("A") ? "B" : "A"}`;

    await expect(unseal(tampered, SECRET, isSession)).resolves.toBe(undefined);
    await expect(unseal(sealed, `${SECRET}-other`, isSession)).resolves.toBe(
      undefined,
    );
    await expect(unseal(sealed, SECRET, isFlow)).resolves.toBe(undefined);
    await expect(unseal("garbage", SECRET, isSession)).resolves.toBe(undefined);
  });
});

describe("returnPath", () => {
  test("keeps paths under /create", () => {
    expect(returnPath("/create?preset=abc")).toBe("/create?preset=abc");
    expect(returnPath("/create/x")).toBe("/create/x");
  });

  test("falls back to /create for anything else", () => {
    expect(returnPath(null)).toBe("/create");
    expect(returnPath("https://evil.example/create")).toBe("/create");
    expect(returnPath("//evil.example/create")).toBe("/create");
    expect(returnPath("/docs")).toBe("/create");
    expect(returnPath("/created")).toBe("/create");
  });
});

test("withDeployFlag sets deploy=1 and keeps the query", () => {
  expect(withDeployFlag("/create?preset=abc&deploy=error")).toBe(
    "/create?preset=abc&deploy=1",
  );
});

test("authorizeUrl asks for a code with an S256 challenge", () => {
  const url = new URL(
    authorizeUrl({
      clientId: "client",
      redirectUri: "https://www.localhost/create/supabase/callback",
      state: "state",
      challenge: "challenge",
    }),
  );

  expect(url.origin).toBe("https://api.supabase.com");
  expect(url.pathname).toBe("/v1/oauth/authorize");
  expect(Object.fromEntries(url.searchParams)).toEqual({
    client_id: "client",
    redirect_uri: "https://www.localhost/create/supabase/callback",
    response_type: "code",
    state: "state",
    code_challenge: "challenge",
    code_challenge_method: "S256",
  });
});

describe("exchangeCode", () => {
  test("posts the code with Basic auth and returns a session", async () => {
    const fetchImpl = tokenFetch({
      access_token: "access",
      refresh_token: "refresh",
      expires_in: 3600,
    });

    const session = await exchangeCode(
      config,
      { code: "code", verifier: "verifier", redirectUri: "https://x/cb" },
      fetchImpl,
      1000,
    );

    expect(session).toEqual({
      accessToken: "access",
      refreshToken: "refresh",
      expiresAt: 1000 + 3_600_000,
    });

    const [url, init] = fetchImpl.mock.calls[0] ?? [];

    expect(String(url)).toBe("https://api.supabase.com/v1/oauth/token");
    expect(new Headers(init?.headers).get("Authorization")).toBe(
      `Basic ${btoa("client:secret")}`,
    );
    expect(Object.fromEntries(new URLSearchParams(String(init?.body)))).toEqual(
      {
        grant_type: "authorization_code",
        code: "code",
        code_verifier: "verifier",
        redirect_uri: "https://x/cb",
      },
    );
  });

  test("throws an OAuthError when Supabase refuses", async () => {
    await expect(
      exchangeCode(
        config,
        { code: "code", verifier: "verifier", redirectUri: "https://x/cb" },
        tokenFetch({ error: "invalid_grant" }, 400),
      ),
    ).rejects.toBeInstanceOf(OAuthError);
  });
});

describe("refreshSession", () => {
  test("refreshes within a minute of expiry", () => {
    expect(needsRefresh({ accessToken: "a", expiresAt: 100_000 }, 30_000)).toBe(
      false,
    );
    expect(needsRefresh({ accessToken: "a", expiresAt: 100_000 }, 50_000)).toBe(
      true,
    );
  });

  test("keeps the old refresh token when Supabase sends none", async () => {
    const session = await refreshSession(
      config,
      { accessToken: "old", refreshToken: "refresh", expiresAt: 0 },
      tokenFetch({ access_token: "new", expires_in: 60 }),
      0,
    );

    expect(session).toEqual({
      accessToken: "new",
      refreshToken: "refresh",
      expiresAt: 60_000,
    });
  });

  test("throws without a refresh token", async () => {
    await expect(
      refreshSession(config, { accessToken: "old", expiresAt: 0 }),
    ).rejects.toBeInstanceOf(OAuthError);
  });
});
