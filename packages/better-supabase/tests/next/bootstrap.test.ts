import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { RemoteCacheKey } from "../../src/next/index.ts";

import { defineAuthorizer } from "../../src/core/authorizer.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { defineSchema } from "../../src/index.ts";
import { createNext, sessionTag } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({
  headers: new Headers(),
  scope: new Map<unknown, Map<string, unknown>>(),
  cacheLife: vi.fn<(profile: unknown) => void>(),
  cacheTag: vi.fn<(...tags: string[]) => void>(),
  updateTag: vi.fn<(tag: string) => undefined>(),
  redirect: vi.fn<(to: string) => never>((to) => {
    throw new Error(`NEXT_REDIRECT ${to}`);
  }),
}));

vi.mock(import("react"), async (original) => ({
  ...(await original()),
  // React's request-scoped cache: one entry per function and arguments until
  // the test starts the next request.
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
  // SAFETY: the code under test reads only getAll from the cookie jar.
  cookies: () => Promise.resolve({ getAll: () => [] } as never),
  headers: () => Promise.resolve(mocks.headers as never),
}));

vi.mock(import("next/cache.js"), () => ({
  cacheLife: mocks.cacheLife,
  cacheTag: mocks.cacheTag,
  updateTag: mocks.updateTag,
  revalidateTag: vi.fn(),
  io: () => Promise.resolve(),
}));

vi.mock(
  import("next/dist/client/components/redirect.js"),
  async (original) => ({ ...(await original()), redirect: mocks.redirect }),
);

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const USER = "11111111-1111-4111-8111-111111111111";
const SESSION = "33333333-3333-4333-8333-333333333333";
const TENANT = "00000000-0000-4000-8000-0000000000aa";
const signer = await createTestSigner();

const signIn = async (claims: Record<string, unknown> = {}): Promise<void> => {
  mocks.headers = new Headers({
    authorization: `Bearer ${await signer.sign({ sub: USER, session_id: SESSION, ...claims })}`,
  });
};

const nextRequest = (): void => {
  mocks.scope.clear();
};

beforeEach(() => {
  nextRequest();
  mocks.headers = new Headers();
  mocks.cacheLife.mockReset();
  mocks.cacheTag.mockReset();
  mocks.updateTag.mockReset();
  mocks.redirect.mockClear();
});

describe("bsb.remote()", () => {
  const bsb = createNext(defineSupabase(schema), {
    env,
    cacheTags: false,
    auth: { jwks: signer.jwks },
  });

  it("hands the caller's session to the remote scope under its key", async () => {
    await signIn({ authz_ver: 4 });
    const keys: RemoteCacheKey[] = [];

    const read = bsb.remote(async (key: RemoteCacheKey, page: string) => {
      keys.push(key);
      const ctx = await bsb.cached({ scope: "remote", key });

      return `${page}:${ctx.auth.kind}:${ctx.session.kind === "user" ? ctx.session.user.id : "-"}`;
    });

    expect(await read("inbox")).toBe(`inbox:user:${USER}`);
    expect(keys[0]).toEqual({
      userId: USER,
      sessionId: SESSION,
      tenant: null,
      authzVersion: 4,
      shared: null,
      support: null,
    });
    expect(mocks.cacheLife).toHaveBeenLastCalledWith({
      stale: 300,
      revalidate: 300,
      expire: 3600,
    });
    expect(mocks.cacheTag).toHaveBeenLastCalledWith(
      sessionTag(USER),
      `bsb:session-id:${SESSION}`,
    );

    // The handoff ends with the call: a key replayed later has no session.
    const late = await bsb.cached({ scope: "remote", key: keys[0]! });
    expect(late.auth).toMatchObject({
      kind: "invalid",
      error: { kind: "unauthorized" },
    });
  });

  it("keys by user or by a shared key when asked", async () => {
    await signIn();
    const keys: RemoteCacheKey[] = [];

    const record = async (key: RemoteCacheKey) => {
      keys.push(key);
    };

    await bsb.remote(record, { share: "user" })();
    await bsb.remote(record, { share: { key: () => "pricing" } })();
    await bsb.remote(async (key: RemoteCacheKey, _id: string) => record(key), {
      tenant: (id) => id,
    })(TENANT);

    expect(keys[0]).toMatchObject({ userId: USER, sessionId: null });
    expect(keys[1]).toMatchObject({
      userId: null,
      sessionId: null,
      authzVersion: null,
      shared: "pricing",
    });
    expect(keys[2]).toMatchObject({ userId: USER, tenant: TENANT });
  });

  it("gives a signed-out caller an anonymous context", async () => {
    const read = bsb.remote(async (key: RemoteCacheKey) => {
      const ctx = await bsb.cached({ scope: "remote", key });

      return ctx.auth.kind;
    });

    expect(await read()).toBe("none");
  });
});

describe("bsb.bootstrap()", () => {
  const seed = vi.fn<(userId: string, version: number) => void>();
  const evicted = vi.fn<(userId: string) => void>();

  const bsb = createNext(defineSupabase(schema), {
    env,
    cacheTags: false,
    auth: { jwks: signer.jwks },
    versions: {
      get: () => undefined,
      set: () => undefined,
      evict: evicted,
      seed,
    } as never,
  });

  let calls: { url: string; body: unknown; profile: string | null }[] = [];
  let row: Record<string, unknown> = {};

  beforeEach(() => {
    calls = [];
    seed.mockReset();
    row = {
      session_active: true,
      authz_version: 7,
      tenant: null,
      data: { unread: 3 },
    };
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
      calls.push({
        url: String(input instanceof Request ? input.url : input),
        body: JSON.parse(String(init?.body ?? "null")),
        profile: new Headers(init?.headers).get("content-profile"),
      });

      return Response.json(row);
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("reads the session, the authz version and the data in one call", async () => {
    await signIn();

    const boot = await bsb.bootstrap<{ unread: number }>({
      rpc: "home",
      args: { page: "inbox" },
    });

    expect(boot).toEqual({
      session: expect.objectContaining({ kind: "user" }),
      sessionActive: true,
      authzVersion: 7,
      tenant: null,
      data: { unread: 3 },
    });
    expect(calls).toEqual([
      {
        url: `${PROJECT_URL}/rest/v1/rpc/bootstrap_home`,
        body: { args: { page: "inbox" } },
        profile: "better_supabase",
      },
    ]);
    expect(seed).toHaveBeenCalledWith(USER, 7);
    expect(mocks.cacheLife).toHaveBeenLastCalledWith({ stale: 300 });
  });

  it("calls once per request for the same arguments", async () => {
    await signIn();
    await Promise.all([
      bsb.bootstrap({ rpc: "home" }),
      bsb.bootstrap({ rpc: "home" }),
      bsb.bootstrap({ rpc: "home", args: { page: 2 } }),
    ]);
    expect(calls).toHaveLength(2);

    nextRequest();
    await bsb.bootstrap({ rpc: "home" });
    expect(calls).toHaveLength(3);
  });

  it("passes the tenant to the wrapper", async () => {
    await signIn();
    row = { ...row, tenant: TENANT };
    const boot = await bsb.bootstrap({ rpc: "home", tenant: TENANT });
    expect(calls[0]?.body).toEqual({ args: { tenant: TENANT } });
    expect(boot.tenant).toBe(TENANT);
  });

  it("keeps an ended session out of the cache and evicts it", async () => {
    await signIn();
    row = { ...row, session_active: false, data: null };
    const boot = await bsb.bootstrap({ rpc: "home" });

    expect(boot).toMatchObject({ sessionActive: false, data: null });
    expect(mocks.cacheLife).toHaveBeenLastCalledWith({
      stale: 0,
      revalidate: 0,
      expire: 0,
    });
    expect(mocks.updateTag).toHaveBeenCalledWith(sessionTag(USER));
    expect(seed).not.toHaveBeenCalled();
  });

  it("redirects an ended session when asked", async () => {
    await signIn();
    row = { ...row, session_active: false, data: null };
    await expect(
      bsb.bootstrap({ rpc: "home", redirect: "/sign-in" }),
    ).rejects.toThrow("NEXT_REDIRECT /sign-in?reason=session_not_found");
  });

  it("skips the call for a signed-out caller", async () => {
    const boot = await bsb.bootstrap({ rpc: "home" });
    expect(boot).toEqual({
      session: { kind: "none", reason: "none" },
      sessionActive: false,
      authzVersion: null,
      tenant: null,
      data: null,
    });
    expect(calls).toEqual([]);
  });

  it("calls the schema gen recorded for the sessions block, unless told otherwise", async () => {
    const recorded = createNext(
      defineSupabase(
        defineSchema({ ...schema.meta, bootstrap: { schema: "api" } }),
      ),
      { env, cacheTags: false, auth: { jwks: signer.jwks } },
    );

    const overridden = createNext(
      defineSupabase(
        defineSchema({ ...schema.meta, bootstrap: { schema: "api" } }),
      ),
      {
        env,
        cacheTags: false,
        auth: { jwks: signer.jwks },
        bootstrapSchema: "app",
      },
    );

    await signIn();
    await recorded.bootstrap({ rpc: "home" });
    await overridden.bootstrap({ rpc: "home" });
    await recorded.bootstrap({ rpc: "home", schema: "own" });

    expect(calls.map((call) => call.profile)).toEqual(["api", "app", "own"]);
  });

  it("throws a DbException when the wrapper is missing", async () => {
    await signIn();
    vi.mocked(globalThis.fetch).mockResolvedValueOnce(
      Response.json(
        { code: "PGRST202", message: "Could not find the function" },
        { status: 404 },
      ),
    );
    await expect(bsb.bootstrap({ rpc: "missing" })).rejects.toMatchObject({
      name: "DbException",
    });
  });
});

describe("bsb.getAccess()", () => {
  const authorizer = defineAuthorizer<"invite" | "export">({
    name: "test",
    key: (ref) => ref,
    evaluate: (request) =>
      request.action === "export"
        ? { outcome: "granted" }
        : { outcome: "denied" },
  });

  const bsb = createNext(defineSupabase(schema), {
    env,
    cacheTags: false,
    auth: { jwks: signer.jwks },
    authorizer,
  });

  it("checks permissions for the request's caller", async () => {
    await signIn({ authz_ver: 2 });
    const access = await bsb.getAccess();

    expect(access.session).toMatchObject({ kind: "user" });
    expect(access.authzVersion).toBe(2);
    expect(await access.can("export")).toBe(true);
    expect(await access.can("invite")).toBe(false);
  });

  it("reuses a snapshot or a bootstrap result", async () => {
    await signIn();
    const snapshot = await bsb.getClaims();
    const fromSnapshot = await bsb.getAccess(snapshot);
    expect(fromSnapshot.session).toMatchObject({ kind: "user" });

    const fromBoot = await bsb.getAccess({
      session: fromSnapshot.session,
      sessionActive: true,
      authzVersion: 9,
      tenant: TENANT,
      data: null,
    });

    expect(fromBoot).toMatchObject({ authzVersion: 9, tenant: TENANT });
  });

  it("denies everything to a signed-out caller", async () => {
    const access = await bsb.getAccess();
    expect(access.session.kind).toBe("none");
    expect(await access.can("export")).toBe(false);
  });
});

describe("root params", () => {
  it("reads locale, brand and tenant, and falls back to the tenant root param", async () => {
    const bsb = createNext(defineSupabase(schema), {
      env,
      cacheTags: false,
      auth: { jwks: signer.jwks },
      rootParams: {
        locale: () => Promise.resolve("nl"),
        brand: () => Promise.reject(new Error("outside the root layout")),
        tenant: () => Promise.resolve(TENANT),
      },
    });

    expect(await bsb.locale()).toBe("nl");
    expect(await bsb.brand()).toBeUndefined();
    expect(await bsb.tenant()).toBe(TENANT);

    await signIn();
    expect((await bsb.context()).db.$context.tenant).toBe(TENANT);
  });

  it("reads nothing without them", async () => {
    const bsb = createNext(defineSupabase(schema), { env, cacheTags: false });
    expect(await bsb.locale()).toBeUndefined();
  });
});
