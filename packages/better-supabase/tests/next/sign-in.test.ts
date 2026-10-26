import { beforeEach, describe, expect, it, vi } from "vitest";

import { readSession } from "../../src/auth/session.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { createNext } from "../../src/next/index.ts";
import { createServer } from "../../src/server/server.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

interface Written {
  readonly value: string;
  readonly options: Record<string, unknown>;
}

const mocks = vi.hoisted(() => ({
  jar: new Map<string, Written>(),
  requestCookies: "",
  scope: new Map<unknown, Map<string, unknown>>(),
  /** Server Actions and route handlers run outside React's request cache. */
  cacheOff: false,
  updateTag: vi.fn<(tag: string) => undefined>(),
}));

vi.mock(import("react"), async (original) => ({
  ...(await original()),
  // React's request-scoped cache: one entry per function and arguments until
  // the test starts the next request.
  cache: ((fn: (...args: unknown[]) => unknown) =>
    (...args: unknown[]) => {
      if (mocks.cacheOff) {
        return fn(...args);
      }

      const entries = mocks.scope.get(fn) ?? new Map<string, unknown>();
      mocks.scope.set(fn, entries);
      const key = JSON.stringify(args);

      if (!entries.has(key)) {
        entries.set(key, fn(...args));
      }

      return entries.get(key);
    }) as never,
}));

vi.mock(import("next/headers.js"), () => ({
  headers: () =>
    Promise.resolve(
      new Headers(
        mocks.requestCookies === "" ? {} : { cookie: mocks.requestCookies },
      ),
    ),
  cookies: () =>
    Promise.resolve(
      // SAFETY: the auth flows read only getAll and set from the cookie jar.
      {
        getAll: () =>
          [...mocks.jar].map(([name, { value }]) => ({ name, value })),
        set: (
          name: string,
          value: string,
          options: Record<string, unknown>,
        ) => {
          if (options["maxAge"] === 0) {
            mocks.jar.delete(name);
          } else {
            mocks.jar.set(name, { value, options });
          }
        },
      } as never,
    ),
}));

vi.mock(import("next/cache.js"), () => ({
  updateTag: mocks.updateTag,
  revalidateTag: () => undefined,
  cacheTag: () => undefined,
  cacheLife: () => undefined,
  io: () => Promise.resolve(),
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const NAME = "sb-abcdefghijklmnopqrst-auth-token";
const VERIFIER = `${NAME}-code-verifier`;
const USER = "11111111-1111-4111-8111-111111111111";
const OTHER = "22222222-2222-4222-8222-222222222222";
const signer = await createTestSigner();

type Fetch = typeof globalThis.fetch;

function tokens(accessToken: string, factors: unknown[] = []): Response {
  return Response.json({
    access_token: accessToken,
    refresh_token: "r1",
    expires_in: 3600,
    user: { id: USER, factors },
  });
}

function callsOf(
  fetch: ReturnType<typeof vi.fn<Fetch>>,
): {
  readonly url: string;
  readonly body: unknown;
  readonly headers: Record<string, string>;
}[] {
  return fetch.mock.calls.map(([input, init]) => ({
    url: String(input),
    body: typeof init?.body === "string" ? JSON.parse(init.body) : undefined,
    // SAFETY: the grants pass headers as a plain object.
    headers: (init?.headers ?? {}) as Record<string, string>,
  }));
}

function setup(
  handler: (url: string) => Response | Promise<Response>,
  extra: {
    readonly cookieScopes?: readonly { readonly domain: string }[];
  } = {},
) {
  const fetch = vi.fn<Fetch>(async (input) => handler(String(input)));
  const betterSupabase = defineSupabase(schema);
  const options = { env, auth: { jwks: signer.jwks, fetch } };
  const server = createServer(betterSupabase, options);

  const bsb = createNext(betterSupabase, {
    ...options,
    ...extra,
    server,
    tenant: () => "org-1",
  });

  return { bsb, server, fetch };
}

/** Starts a new request carrying the cookies written so far. */
function nextRequest(): void {
  mocks.scope.clear();
  mocks.requestCookies = [...mocks.jar]
    .map(([name, { value }]) => `${name}=${encodeURIComponent(value)}`)
    .join("; ");
}

function sessionToken(): string | undefined {
  const cookies = [...mocks.jar].map(([name, { value }]) => ({ name, value }));

  return readSession(cookies, NAME)?.access_token;
}

describe("auth flows", () => {
  beforeEach(() => {
    mocks.jar.clear();
    mocks.requestCookies = "";
    mocks.scope.clear();
    mocks.cacheOff = false;
    mocks.updateTag.mockClear();
  });

  it("signs in, writes the session, stores it for the render and checks next", async () => {
    const token = await signer.sign({ sub: USER });
    const { bsb, fetch } = setup(() => tokens(token));

    const signed = await bsb.signIn(
      { email: "a@b.test", password: "pw", next: "//evil.test" },
      { fallback: "/en" },
    );

    expect(signed).toEqual({
      ok: true,
      data: { redirectTo: "/en", mfa: false },
      error: null,
    });
    expect(fetch).toHaveBeenCalledOnce();
    expect(callsOf(fetch)[0]).toMatchObject({
      url: `${PROJECT_URL}/auth/v1/token?grant_type=password`,
      body: { email: "a@b.test", password: "pw" },
    });
    expect(sessionToken()).toBe(token);

    const before = bsb.sessions.stats();

    const snapshot = await bsb.snapshot(
      new Request("https://app.test/", {
        headers: { authorization: `Bearer ${token}` },
      }),
    );

    expect(snapshot?.userId).toBe(USER);
    expect(bsb.sessions.stats().misses).toBe(before.misses);
    expect(bsb.sessions.stats().hits).toBe(before.hits + 1);
  });

  it("keeps signInWithPassword as the same flow", async () => {
    const token = await signer.sign({ sub: USER });
    const { bsb } = setup(() => tokens(token));

    const signed = await bsb.signInWithPassword({
      email: "a@b.test",
      password: "pw",
      next: "/inbox?tab=1",
    });

    expect(signed.data?.redirectTo).toBe("/inbox?tab=1");
    expect(sessionToken()).toBe(token);
  });

  it("rejects every next that could leave the origin", async () => {
    const token = await signer.sign({ sub: USER });
    const { bsb } = setup(() => tokens(token));

    for (const next of [
      "https://evil.test",
      "//evil.test",
      "/\\evil.test",
      "/ok\nevil",
      null,
    ]) {
      const signed = await bsb.signIn(
        { email: "a@b.test", password: "pw", next },
        { fallback: "/home" },
      );

      expect(signed.data?.redirectTo).toBe("/home");
    }
  });

  it("maps Auth errors without Auth's message and writes nothing", async () => {
    const answers: Response[] = [
      Response.json(
        { error_code: "invalid_credentials", msg: "Invalid login credentials" },
        { status: 400 },
      ),
      Response.json(
        { error_code: "over_request_rate_limit", msg: "slow down" },
        { status: 429 },
      ),
      Response.json({ msg: "boom" }, { status: 502 }),
      new Response("not json", { status: 400 }),
      Response.json({ msg: "pending" }),
    ];

    const { bsb } = setup(() => answers.shift() ?? Response.error());
    const results = [];

    for (let index = 0; index < 5; index += 1) {
      results.push(await bsb.signIn({ email: "a@b.test", password: "no" }));
    }

    expect(results.map((result) => result.error)).toMatchObject([
      { kind: "unauthorized", code: "invalid_credentials" },
      { kind: "rate_limited", code: "over_request_rate_limit" },
      { kind: "network" },
      { kind: "unauthorized" },
      { kind: "unauthorized", code: "no_session" },
    ]);

    for (const result of results) {
      expect(result.error?.message).not.toMatch(/Invalid|slow|boom|pending/);
    }

    expect(mocks.jar.size).toBe(0);
  });

  it("reports network failures and timeouts", async () => {
    const thrown = setup(() => {
      throw new TypeError("connect ECONNREFUSED");
    });

    expect(
      (await thrown.bsb.signIn({ email: "a@b.test", password: "pw" })).error,
    ).toMatchObject({ kind: "network", message: "connect ECONNREFUSED" });

    const odd = setup(() => Promise.reject("down"));

    expect(
      (await odd.bsb.signIn({ email: "a@b.test", password: "pw" })).error,
    ).toMatchObject({ kind: "network", message: "fetch failed" });

    const fetch = vi.fn<Fetch>(
      async (_input, init) =>
        new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener("abort", () => {
            reject(new Error("aborted"));
          });
        }),
    );

    const slow = createNext(defineSupabase(schema), {
      env,
      auth: { jwks: signer.jwks, fetch, refreshTimeoutMs: 1 },
    });

    expect(
      (await slow.signIn({ email: "a@b.test", password: "pw" })).error,
    ).toMatchObject({ kind: "timeout" });
  });

  it("refuses a session whose token does not verify", async () => {
    const other = await createTestSigner();
    const token = await other.sign({ sub: USER });
    const { bsb } = setup(() => tokens(token));

    const signed = await bsb.signIn({ email: "a@b.test", password: "pw" });

    expect(signed).toMatchObject({
      ok: false,
      error: { kind: "unauthorized" },
    });
    expect(mocks.jar.size).toBe(0);
  });

  it("forwards the caller's IP with the secret key", async () => {
    const token = await signer.sign({ sub: USER });
    const fetch = vi.fn<Fetch>(async () => tokens(token));

    const bsb = createNext(defineSupabase(schema), {
      env: { ...env, secretKey: "sb_secret_test" },
      auth: { jwks: signer.jwks, fetch, clientIp: () => "203.0.113.9" },
    });

    await bsb.signIn({ email: "a@b.test", password: "pw" });

    expect(callsOf(fetch)[0]?.headers).toMatchObject({
      apikey: "sb_secret_test",
      "sb-forwarded-for": "203.0.113.9",
    });
  });

  it("reads before sign-in and after it in the same request", async () => {
    const token = await signer.sign({
      sub: USER,
      app_metadata: { tenant_id: "org-1" },
    });

    const { bsb } = setup(() => tokens(token));

    expect(await bsb.getRequestSession()).toBeNull();
    expect((await bsb.session()).kind).toBe("anon");
    expect((await bsb.context()).auth.kind).toBe("anon");
    expect((await bsb.context({ tenant: "org-1" })).auth.kind).toBe("anon");

    const signed = await bsb.signIn({ email: "a@b.test", password: "pw" });

    expect((await bsb.getRequestSession())?.userId).toBe(USER);
    expect(await bsb.session()).toMatchObject({
      kind: "user",
      user: { id: USER },
    });
    expect((await bsb.context()).auth.kind).toBe("user");
    expect((await bsb.context({ tenant: "org-1" })).auth).toMatchObject({
      kind: "user",
      user: { id: USER },
    });

    // Plain data only: the token stays in the cookie and on the request's reads.
    expect(Object.keys(signed.data ?? {})).toEqual(["redirectTo", "mfa"]);
  });

  it("reads the jar in a Server Action, where React's cache is off", async () => {
    const token = await signer.sign({ sub: USER });

    const { bsb } = setup((url) =>
      url.includes("logout")
        ? new Response(null, { status: 204 })
        : tokens(token),
    );

    mocks.cacheOff = true;

    expect(await bsb.getRequestSession()).toBeNull();

    await bsb.signIn({ email: "a@b.test", password: "pw" });

    expect((await bsb.getRequestSession())?.userId).toBe(USER);
    expect((await bsb.context({ tenant: "org-1" })).auth.kind).toBe("user");

    await bsb.signOut();

    expect(await bsb.getRequestSession()).toBeNull();
    expect((await bsb.session()).kind).toBe("anon");
  });

  it("resolves once for a render that never commits", async () => {
    const token = await signer.sign({ sub: USER });
    const { bsb, server } = setup(() => tokens(token));

    await bsb.signIn({ email: "a@b.test", password: "pw" });
    nextRequest();

    const resolve = vi.spyOn(server, "resolve");
    const [first, second] = await Promise.all([bsb.session(), bsb.session()]);

    await bsb.context();
    await bsb.context({ tenant: "org-1" });
    await bsb.getRequestSession();

    expect(first).toBe(second);
    expect(first.kind).toBe("user");
    expect(resolve).toHaveBeenCalledOnce();
  });

  it("signs out on the Auth server first, then clears the cookies", async () => {
    const token = await signer.sign({ sub: USER });
    const order: string[] = [];

    const { bsb, fetch } = setup(
      (url) => {
        order.push(url.includes("logout") ? "logout" : "grant");

        return url.includes("logout")
          ? new Response(null, { status: 204 })
          : tokens(token);
      },
      { cookieScopes: [{ domain: ".old.test" }] },
    );

    await bsb.signIn({ email: "a@b.test", password: "pw" });
    nextRequest();

    expect((await bsb.session()).kind).toBe("user");

    const signedOut = await bsb.signOut({ scope: "global", next: "/bye" });

    expect(signedOut).toEqual({
      ok: true,
      data: { redirectTo: "/bye", mfa: false },
      error: null,
    });
    expect(order).toEqual(["grant", "logout"]);
    expect(callsOf(fetch)[1]).toMatchObject({
      url: `${PROJECT_URL}/auth/v1/logout?scope=global`,
      headers: { authorization: `Bearer ${token}` },
    });
    expect(sessionToken()).toBeUndefined();
    expect(mocks.updateTag).toHaveBeenCalledWith(expect.stringContaining(USER));
    expect(await bsb.getRequestSession()).toBeNull();
    expect((await bsb.session()).kind).toBe("anon");
    expect((await bsb.context({ tenant: "org-1" })).auth.kind).toBe("anon");
  });

  it("treats a session Auth already ended as signed out", async () => {
    const token = await signer.sign({ sub: USER });

    const { bsb } = setup((url) =>
      url.includes("logout")
        ? Response.json({ error_code: "session_not_found" }, { status: 404 })
        : tokens(token),
    );

    await bsb.signIn({ email: "a@b.test", password: "pw" });
    nextRequest();

    expect((await bsb.signOut()).ok).toBe(true);
    expect(sessionToken()).toBeUndefined();
  });

  it("keeps the cookies when the revoke fails", async () => {
    const token = await signer.sign({ sub: USER });

    const { bsb } = setup((url) =>
      url.includes("logout")
        ? new Response(null, { status: 503 })
        : tokens(token),
    );

    await bsb.signIn({ email: "a@b.test", password: "pw" });
    nextRequest();

    expect((await bsb.signOut()).error).toMatchObject({ kind: "network" });
    expect(sessionToken()).toBe(token);
  });

  it("keeps this session when signing out the others", async () => {
    const token = await signer.sign({ sub: USER });

    const { bsb, fetch } = setup((url) =>
      url.includes("logout")
        ? new Response(null, { status: 204 })
        : tokens(token),
    );

    await bsb.signIn({ email: "a@b.test", password: "pw" });
    nextRequest();

    const kept = await bsb.signOut({ scope: "others" });

    expect(kept.data).toEqual({ redirectTo: "/", mfa: false });
    expect(callsOf(fetch)[1]?.url).toContain("scope=others");
    expect(sessionToken()).toBe(token);
    expect((await bsb.getRequestSession())?.userId).toBe(USER);
    // The other sessions' tokens stay valid, so their memo entries and tags go.
    expect(mocks.updateTag).toHaveBeenCalledWith(expect.stringContaining(USER));
  });

  it("signs out a signed-out caller without calling Auth", async () => {
    const { bsb, fetch } = setup(() => Response.error());

    expect((await bsb.signOut()).data).toEqual({ redirectTo: "/", mfa: false });
    expect(fetch).not.toHaveBeenCalled();
  });

  it("verifies a token_hash and an emailed code", async () => {
    const token = await signer.sign({ sub: USER });
    const { bsb, fetch } = setup(() => tokens(token));

    const linked = await bsb.verifyOtp({
      type: "magiclink",
      tokenHash: "hash",
      next: "/welcome",
    });

    const coded = await bsb.verifyOtp({
      type: "email",
      email: "a@b.test",
      token: "123456",
    });

    expect(linked.data?.redirectTo).toBe("/welcome");
    expect(coded.data?.redirectTo).toBe("/");
    expect((await bsb.getRequestSession())?.userId).toBe(USER);
    expect(callsOf(fetch).map((call) => [call.url, call.body])).toEqual([
      [
        `${PROJECT_URL}/auth/v1/verify`,
        { type: "magiclink", token_hash: "hash" },
      ],
      [
        `${PROJECT_URL}/auth/v1/verify`,
        { type: "email", email: "a@b.test", token: "123456" },
      ],
    ]);
    expect(sessionToken()).toBe(token);
  });

  it("replaces the session a link lands on instead of merging it", async () => {
    const first = await signer.sign({ sub: USER });
    const second = await signer.sign({ sub: OTHER });
    const answers = [tokens(first), tokens(second)];
    const { bsb } = setup(() => answers.shift() ?? Response.error());

    await bsb.signIn({ email: "a@b.test", password: "pw" });
    nextRequest();

    const verified = await bsb.verifyOtp({ type: "invite", tokenHash: "h" });

    expect(verified.ok).toBe(true);
    expect((await bsb.getRequestSession())?.userId).toBe(OTHER);
    expect(sessionToken()).toBe(second);
    expect(await bsb.session()).toMatchObject({ user: { id: OTHER } });
  });

  it("starts OAuth with a PKCE verifier cookie and exchanges the code once", async () => {
    const token = await signer.sign({ sub: USER });
    const { bsb, fetch } = setup(() => tokens(token));

    const { url } = await bsb.authorizeUrl({
      provider: "github",
      redirectTo: "https://app.test/auth/callback",
      next: "/projects",
      scopes: "read:user",
      queryParams: { prompt: "consent", code_challenge: "forged" },
    });

    const target = new URL(url);
    const verifier = mocks.jar.get(VERIFIER);

    expect(target.origin + target.pathname).toBe(
      `${PROJECT_URL}/auth/v1/authorize`,
    );
    expect(Object.fromEntries(target.searchParams)).toMatchObject({
      provider: "github",
      redirect_to: "https://app.test/auth/callback?next=%2Fprojects",
      code_challenge_method: "s256",
      scopes: "read:user",
      prompt: "consent",
    });
    expect(verifier?.options).toMatchObject({
      httpOnly: true,
      sameSite: "lax",
      maxAge: 600,
      path: "/",
    });

    const challenge = new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(verifier?.value),
      ),
    );

    expect(target.searchParams.get("code_challenge")).toBe(
      Buffer.from(challenge).toString("base64url"),
    );

    nextRequest();

    const exchanged = await bsb.exchangeCode({ code: "c1", next: "/projects" });

    expect(exchanged.data?.redirectTo).toBe("/projects");
    expect(callsOf(fetch)[0]).toMatchObject({
      url: `${PROJECT_URL}/auth/v1/token?grant_type=pkce`,
      body: { auth_code: "c1", code_verifier: verifier?.value },
    });
    expect(mocks.jar.has(VERIFIER)).toBe(false);
    expect(sessionToken()).toBe(token);

    const replayed = await bsb.exchangeCode({ code: "c1" });

    expect(replayed.error).toMatchObject({
      kind: "unauthorized",
      code: "code_verifier_missing",
    });
    expect(fetch).toHaveBeenCalledOnce();
  });

  it("drops an unsafe next from the OAuth callback", async () => {
    const { bsb } = setup(() => Response.error());

    const { url } = await bsb.authorizeUrl({
      provider: "google",
      redirectTo: "https://app.test/auth/callback",
      next: "https://evil.test",
    });

    expect(new URL(url).searchParams.get("redirect_to")).toBe(
      "https://app.test/auth/callback",
    );
  });

  it("deletes the verifier when the exchange fails", async () => {
    const { bsb } = setup(() =>
      Response.json({ error_code: "flow_state_expired" }, { status: 400 }),
    );

    await bsb.authorizeUrl({
      provider: "github",
      redirectTo: "https://app.test/cb",
    });

    const exchanged = await bsb.exchangeCode({ code: "old" });

    expect(exchanged.error).toMatchObject({ code: "flow_state_expired" });
    expect(mocks.jar.has(VERIFIER)).toBe(false);
  });

  it("verifies MFA and commits the aal2 session", async () => {
    const factors = [{ id: "f1", status: "verified" }];
    const aal1 = await signer.sign({ sub: USER, aal: "aal1" });
    const aal2 = await signer.sign({ sub: USER, aal: "aal2" });

    const { bsb, fetch } = setup((url) => {
      if (url.endsWith("/challenge")) {
        return Response.json({ id: "ch1", type: "totp" });
      }

      return tokens(url.endsWith("/verify") ? aal2 : aal1, factors);
    });

    const signed = await bsb.signIn({ email: "a@b.test", password: "pw" });

    expect(signed.data?.mfa).toBe(true);

    const verified = await bsb.verifyMfa({
      factorId: "f1",
      code: "123456",
      next: "/secure",
    });

    expect(verified).toMatchObject({
      ok: true,
      data: { redirectTo: "/secure", mfa: false },
    });
    expect(callsOf(fetch).slice(1)).toMatchObject([
      {
        url: `${PROJECT_URL}/auth/v1/factors/f1/challenge`,
        headers: { authorization: `Bearer ${aal1}` },
      },
      {
        url: `${PROJECT_URL}/auth/v1/factors/f1/verify`,
        body: { challenge_id: "ch1", code: "123456" },
        headers: { authorization: `Bearer ${aal1}` },
      },
    ]);
    expect(sessionToken()).toBe(aal2);
    expect((await bsb.getRequestSession())?.claims["aal"]).toBe("aal2");
  });

  it("refuses MFA without a session or a challenge id", async () => {
    const token = await signer.sign({ sub: USER });

    const { bsb } = setup((url) =>
      url.endsWith("/challenge")
        ? Response.json({ type: "totp" })
        : tokens(token),
    );

    expect(
      (await bsb.verifyMfa({ factorId: "f1", code: "1" })).error,
    ).toMatchObject({ kind: "unauthorized" });

    await bsb.signIn({ email: "a@b.test", password: "pw" });

    expect(
      (await bsb.verifyMfa({ factorId: "f1", code: "1" })).error,
    ).toMatchObject({ kind: "unauthorized", message: "MFA challenge failed" });
  });

  it("passes a failed challenge through", async () => {
    const token = await signer.sign({ sub: USER });

    const { bsb } = setup((url) =>
      url.endsWith("/challenge")
        ? Response.json({ error_code: "mfa_factor_not_found" }, { status: 404 })
        : tokens(token),
    );

    await bsb.signIn({ email: "a@b.test", password: "pw" });

    expect(
      (await bsb.verifyMfa({ factorId: "f1", code: "1" })).error,
    ).toMatchObject({ code: "mfa_factor_not_found" });
  });
});
