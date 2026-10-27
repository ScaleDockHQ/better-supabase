import { createClient } from "@supabase/supabase-js";
import { Pool } from "pg";
import {
  afterAll,
  beforeAll,
  beforeEach,
  describe,
  expect,
  it,
  vi,
} from "vitest";

import { readSession, sessionCookieName } from "../../src/auth/session.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { parseEnv } from "../../src/env/index.ts";
import { createNext } from "../../src/next/index.ts";
import { createServer } from "../../src/server/server.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { stackDbUrl, stackUrl } from "./stack-env.ts";

const mocks = vi.hoisted(() => ({
  jar: new Map<string, string>(),
  requestCookies: "",
  scope: new Map<unknown, Map<string, unknown>>(),
}));

vi.mock(import("react"), async (original) => ({
  ...(await original()),
  // React's request-scoped cache, until the test starts the next request.
  cache: ((fn: (...args: unknown[]) => unknown) =>
    (...args: unknown[]) => {
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
        getAll: () => [...mocks.jar].map(([name, value]) => ({ name, value })),
        set: (name: string, value: string, options: { maxAge?: number }) => {
          if (options.maxAge === 0) {
            mocks.jar.delete(name);
          } else {
            mocks.jar.set(name, value);
          }
        },
      } as never,
    ),
}));

vi.mock(import("next/cache.js"), () => ({
  updateTag: () => undefined,
  revalidateTag: () => undefined,
  cacheTag: () => undefined,
  cacheLife: () => undefined,
  io: () => Promise.resolve(),
}));

const url = stackUrl();
const dbUrl = stackDbUrl();

const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";

const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";

async function reachable(): Promise<boolean> {
  try {
    const response = await fetch(`${url}/auth/v1/health`, {
      headers: { apikey: publishableKey },
      signal: AbortSignal.timeout(1000),
    });

    return response.ok;
  } catch {
    return false;
  }
}

const live = await reachable();

/** Starts a new request carrying the cookies written so far. */
function nextRequest(): void {
  mocks.scope.clear();
  mocks.requestCookies = [...mocks.jar]
    .map(([name, value]) => `${name}=${encodeURIComponent(value)}`)
    .join("; ");
}

const BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

/** The current RFC 6238 code for a base32 secret. */
async function totp(secret: string): Promise<string> {
  const bits = secret
    .replace(/[=]+$/, "")
    .toUpperCase()
    .replaceAll(/./g, (char) =>
      BASE32.indexOf(char).toString(2).padStart(5, "0"),
    );

  const bytes = new Uint8Array(Math.floor(bits.length / 8)).map((_, index) =>
    Number.parseInt(bits.slice(index * 8, index * 8 + 8), 2),
  );

  const counter = new DataView(new ArrayBuffer(8));
  counter.setBigUint64(0, BigInt(Math.floor(Date.now() / 30_000)));

  const key = await crypto.subtle.importKey(
    "raw",
    bytes,
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );

  const mac = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, counter.buffer),
  );

  const offset = (mac[19] ?? 0) % 16;
  const view = new DataView(mac.buffer, offset, 4);

  return String((view.getUint32(0) % 2 ** 31) % 1_000_000).padStart(6, "0");
}

describe.skipIf(!live)("Next.js auth flows against Supabase Auth", () => {
  const env = parseEnv({
    SUPABASE_URL: url,
    SUPABASE_PUBLISHABLE_KEY: publishableKey,
  }).env!;

  const admin = createClient(url, secretKey, {
    auth: { persistSession: false },
  });

  const password = "correct horse battery staple 42";
  const users: string[] = [];
  let pool: Pool;

  async function createUser(): Promise<{ id: string; email: string }> {
    const email = `next-auth-${crypto.randomUUID()}@example.com`;

    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });

    if (error) {
      throw error;
    }

    users.push(data.user.id);

    return { id: data.user.id, email };
  }

  function setup() {
    const betterSupabase = defineSupabase(schema);
    const server = createServer(betterSupabase, { env });
    const bsb = createNext(betterSupabase, { env, server });
    const name = sessionCookieName(url);

    const token = (): string | undefined =>
      readSession(
        [...mocks.jar].map(([cookie, value]) => ({ name: cookie, value })),
        name,
      )?.access_token;

    return { bsb, server, token, verifier: `${name}-code-verifier` };
  }

  // Vitest still runs the body of a skipped suite, so nothing here may touch the stack.
  beforeAll(() => {
    pool = new Pool({ connectionString: dbUrl, max: 1 });
  });

  beforeEach(() => {
    mocks.jar.clear();
    mocks.requestCookies = "";
    mocks.scope.clear();
  });

  afterAll(async () => {
    await Promise.all(users.map((id) => admin.auth.admin.deleteUser(id)));
    await pool.end();
  });

  it("signs in with a password and reads the session in the same request", async () => {
    const user = await createUser();
    const { bsb, server, token } = setup();

    expect(await bsb.getClaims()).toBeNull();
    expect((await bsb.context({ tenant: "org-1" })).auth.kind).toBe("none");

    const signed = await bsb.signInWithPassword(
      { email: user.email, password, next: "https://evil.test" },
      { fallback: "/home" },
    );

    expect(signed).toMatchObject({
      ok: true,
      data: {
        redirectTo: "/home",
        mfa: false,
        user: { id: user.id, email: user.email },
      },
    });
    expect(token()).toBeDefined();
    expect((await bsb.getClaims())?.userId).toBe(user.id);
    expect(await bsb.claims()).toMatchObject({ user: { id: user.id } });
    expect((await bsb.context({ tenant: "org-1" })).auth.kind).toBe("user");

    nextRequest();
    const resolve = vi.spyOn(server, "resolve");

    await Promise.all([bsb.claims(), bsb.context(), bsb.getClaims()]);

    expect(resolve).toHaveBeenCalledOnce();
  });

  it("refuses a wrong password without Auth's message", async () => {
    const user = await createUser();
    const { bsb } = setup();

    const signed = await bsb.signInWithPassword({
      email: user.email,
      password: "wrong",
    });

    expect(signed.error).toMatchObject({
      kind: "unauthorized",
      code: "invalid_credentials",
      message: "Sign-in failed",
    });
    expect(mocks.jar.size).toBe(0);
  });

  it("verifies a magic link token_hash and an emailed code", async () => {
    const user = await createUser();
    const { bsb, token } = setup();

    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email: user.email,
    });

    const linked = await bsb.verifyOtp({
      type: "magiclink",
      tokenHash: link.data.properties?.hashed_token ?? "",
      next: "/welcome",
    });

    expect(linked).toMatchObject({
      ok: true,
      data: { redirectTo: "/welcome", mfa: false },
    });
    expect((await bsb.getClaims())?.userId).toBe(user.id);
    expect(token()).toBeDefined();

    const reused = await bsb.verifyOtp({
      type: "magiclink",
      tokenHash: link.data.properties?.hashed_token ?? "",
    });

    expect(reused.error).toMatchObject({ kind: "unauthorized" });

    const code = await admin.auth.admin.generateLink({
      type: "magiclink",
      email: user.email,
    });

    const coded = await bsb.verifyOtp({
      type: "email",
      email: user.email,
      token: code.data.properties?.email_otp ?? "",
    });

    expect(coded.ok).toBe(true);
    expect((await bsb.getClaims())?.userId).toBe(user.id);
  });

  it("emails a magic link with signInWithOtp and exchanges its code", async () => {
    const user = await createUser();
    const { bsb, token, verifier } = setup();
    const callback = "https://example.localhost/auth/callback";

    const sent = await bsb.signInWithOtp({
      email: user.email,
      redirectTo: callback,
      next: "/projects",
      shouldCreateUser: false,
    });

    expect(sent).toEqual({ ok: true, data: null, error: null });
    expect(mocks.jar.has(verifier)).toBe(true);

    const { rows } = await pool.query<{ token_hash: string }>(
      "select token_hash from auth.one_time_tokens where user_id = $1",
      [user.id],
    );

    const link = new URL(`${url}/auth/v1/verify`);
    link.searchParams.set("token", rows[0]?.token_hash ?? "");
    link.searchParams.set("type", "magiclink");
    link.searchParams.set("redirect_to", `${callback}?next=%2Fprojects`);

    const landed = await fetch(link, { redirect: "manual" });
    const location = new URL(landed.headers.get("location") ?? "", url);
    const code = location.searchParams.get("code") ?? "";

    expect(code).not.toBe("");
    expect(location.searchParams.get("next")).toBe("/projects");

    nextRequest();

    const exchanged = await bsb.exchangeCodeForSession({
      code,
      next: "/projects",
    });

    expect(exchanged.error).toBeNull();
    expect(exchanged).toMatchObject({
      ok: true,
      data: {
        redirectTo: "/projects",
        mfa: false,
        user: { id: user.id, email: user.email },
      },
    });
    expect(mocks.jar.has(verifier)).toBe(false);
    expect((await bsb.getClaims())?.userId).toBe(user.id);
    expect(token()).toBe((await bsb.getClaims())?.accessToken);
  });

  it("commits the session signUp returns when confirmation is off", async () => {
    const { bsb, token, verifier } = setup();
    const email = `next-auth-${crypto.randomUUID()}@example.com`;

    const signed = await bsb.signUp({
      email,
      password,
      redirectTo: "https://example.localhost/auth/callback",
      next: "/welcome",
      data: { name: "New" },
    });

    const userId =
      signed.data !== null && "user" in signed.data
        ? (signed.data.user?.id ?? "")
        : "";

    users.push(userId);

    expect(signed).toMatchObject({
      ok: true,
      data: {
        redirectTo: "/welcome",
        mfa: false,
        user: { email, userMetadata: { name: "New" } },
      },
    });
    expect(mocks.jar.has(verifier)).toBe(false);
    expect((await bsb.getClaims())?.userId).toBe(userId);
    expect(token()).toBeDefined();
  });

  it("verifies TOTP and commits the aal2 session", async () => {
    const user = await createUser();
    const { bsb } = setup();

    expect(
      (await bsb.signInWithPassword({ email: user.email, password })).ok,
    ).toBe(true);
    const accessToken = (await bsb.getClaims())?.accessToken ?? "";

    const enrolled = await fetch(`${url}/auth/v1/factors`, {
      method: "POST",
      headers: {
        apikey: publishableKey,
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ factor_type: "totp", friendly_name: "app" }),
    });

    // SAFETY: Auth answers an enrolment with the factor id and its TOTP secret.
    const factor = (await enrolled.json()) as {
      id: string;
      totp: { secret: string };
    };

    const verified = await bsb.verifyMfa({
      factorId: factor.id,
      code: await totp(factor.totp.secret),
      next: "/secure",
    });

    expect(verified).toMatchObject({
      ok: true,
      data: { redirectTo: "/secure", mfa: false },
    });
    expect((await bsb.getClaims())?.claims["aal"]).toBe("aal2");

    mocks.jar.clear();
    nextRequest();

    const again = await bsb.signInWithPassword({ email: user.email, password });

    expect(again.data?.mfa).toBe(true);
  });

  it("revokes the session in Auth, then clears the cookies", async () => {
    const user = await createUser();
    const { bsb, token } = setup();

    expect(
      (await bsb.signInWithPassword({ email: user.email, password })).ok,
    ).toBe(true);
    const accessToken = (await bsb.getClaims())?.accessToken ?? "";

    nextRequest();
    expect((await bsb.claims()).kind).toBe("user");

    const signedOut = await bsb.signOut({ next: "/signed-out" });

    expect(signedOut).toEqual({
      ok: true,
      data: { redirectTo: "/signed-out", mfa: false, user: null },
      error: null,
    });
    expect(token()).toBeUndefined();
    expect(await bsb.getClaims()).toBeNull();
    expect((await bsb.context({ tenant: "org-1" })).auth.kind).toBe("none");

    const ended = await fetch(`${url}/auth/v1/user`, {
      headers: {
        apikey: publishableKey,
        authorization: `Bearer ${accessToken}`,
      },
    });

    expect(ended.ok).toBe(false);
  });
});
