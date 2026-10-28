import type * as ServerCore from "@supabase/server/core";
import type * as SupabaseJs from "@supabase/supabase-js";

import * as v from "valibot";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { cachedLife } from "../../src/next/cache.ts";
import { createNext, sessionTag } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({
  headers: new Headers(),
  cacheLife: vi.fn<(profile: unknown) => void>(),
  cacheTag: vi.fn<(...tags: string[]) => void>(),
  updateTag: vi.fn<(tag: string) => void>(),
  verifications: 0,
  clients: 0,
}));

vi.mock("next/headers.js", () => ({
  cookies: () =>
    Promise.resolve({
      getAll: () =>
        (mocks.headers.get("cookie") ?? "")
          .split("; ")
          .filter(Boolean)
          .map((pair) => ({
            name: pair.slice(0, pair.indexOf("=")),
            value: decodeURIComponent(pair.slice(pair.indexOf("=") + 1)),
          })),
    }),
  headers: () => Promise.resolve(mocks.headers),
}));

vi.mock("next/cache.js", () => ({
  cacheLife: mocks.cacheLife,
  cacheTag: mocks.cacheTag,
  updateTag: mocks.updateTag,
  revalidateTag: vi.fn(),
  io: () => Promise.resolve(),
}));

vi.mock("@supabase/server/core", async (original) => {
  const actual = await original<typeof ServerCore>();

  return {
    ...actual,
    verifyCredentials: (
      ...args: Parameters<typeof actual.verifyCredentials>
    ) => {
      mocks.verifications += 1;

      return actual.verifyCredentials(...args);
    },
  };
});

vi.mock("@supabase/supabase-js", async (original) => {
  const actual = await original<typeof SupabaseJs>();

  return {
    ...actual,
    createClient: (...args: Parameters<typeof actual.createClient>) => {
      mocks.clients += 1;

      return actual.createClient(...args);
    },
  };
});

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

describe("private-cache scopes", () => {
  const betterSupabase = defineSupabase(schema);

  const bsb = createNext(betterSupabase, {
    env,
    cacheTags: false,
    auth: { jwks: signer.jwks },
  });

  beforeEach(() => {
    mocks.verifications = 0;
    mocks.clients = 0;
    mocks.cacheLife.mockReset();
    mocks.cacheTag.mockReset();
  });

  it("verifies a token once and builds clients only when used", async () => {
    const token = await signer.sign({ sub: USER });
    const bearer = { authorization: `Bearer ${token}` };

    // Twelve islands, each its own scope: four read data, eight only the session.
    for (let island = 0; island < 12; island += 1) {
      const ctx = await bsb.context(
        new Request("https://app.test/", { headers: bearer }),
      );

      expect(ctx.auth.kind).toBe("user");

      if (island % 3 === 0) {
        void ctx.db.customers;
      }
    }

    expect(mocks.verifications).toBe(1);
    // A user's ctx.db runs on a bare PostgREST client.
    expect(mocks.clients).toBe(0);

    const ctx = await bsb.context(
      new Request("https://app.test/", { headers: bearer }),
    );

    expect(ctx.db.$client).toBe(ctx.supabase);
    expect(mocks.clients).toBe(1);
  });

  it("caches per session with the App Shell floor, not the token's lifetime", async () => {
    const token = await signer.sign({ sub: USER, expiresIn: 120 });
    mocks.headers = new Headers({ authorization: `Bearer ${token}` });
    const ctx = await bsb.cached({ life: { expire: 3600 } });
    expect(ctx.session).toMatchObject({ kind: "user", user: { id: USER } });
    expect(ctx.auth.kind).toBe("user");
    expect(mocks.cacheLife).toHaveBeenLastCalledWith({
      stale: 300,
      expire: 3600,
    });
    expect(mocks.cacheTag).toHaveBeenCalledWith(sessionTag(USER));

    await bsb.cached({ life: { capToToken: true } });
    const [life] = mocks.cacheLife.mock.lastCall! as [{ stale: number }];
    expect(life.stale).toBeGreaterThan(100);
    expect(life.stale).toBeLessThanOrEqual(120);

    await bsb.evictSession(USER);
    expect(mocks.updateTag).toHaveBeenCalledWith(`bsb:session:${USER}`);
  });

  it("adds tags and caps stale with life.stale", async () => {
    const token = await signer.sign({ sub: USER, expiresIn: 3600 });
    mocks.headers = new Headers({ authorization: `Bearer ${token}` });
    const tags = [`authz:${USER}`, "organization:acme"];
    await bsb.cached({ tags, life: { stale: 45 } });
    expect(mocks.cacheLife).toHaveBeenLastCalledWith({ stale: 45 });
    expect(mocks.cacheTag).toHaveBeenLastCalledWith(sessionTag(USER), ...tags);

    await bsb.cached({ life: { stale: 900 } });
    expect(mocks.cacheLife).toHaveBeenLastCalledWith({ stale: 900 });

    mocks.headers = new Headers();
    await bsb.cached({ tags: ["public:pricing"] });
    expect(mocks.cacheTag).toHaveBeenLastCalledWith("public:pricing");
    mocks.cacheTag.mockReset();
    await bsb.cached();
    expect(mocks.cacheTag).not.toHaveBeenCalled();

    mocks.updateTag.mockReset();
    await bsb.evictSession(USER, { tags: [`authz:${USER}`] });
    expect(mocks.updateTag.mock.calls).toEqual([
      [sessionTag(USER)],
      [`authz:${USER}`],
    ]);
  });

  it("builds a context from a snapshot without verifying again", async () => {
    mocks.headers = new Headers({
      authorization: `Bearer ${await signer.sign({ sub: USER })}`,
    });
    const snapshot = await bsb.getClaims();
    expect(snapshot?.userId).toBe(USER);
    const verified = mocks.verifications;

    const ctx = await bsb.contextFromSession(snapshot);
    expect(ctx.auth).toMatchObject({ kind: "user", user: { id: USER } });
    expect(mocks.verifications).toBe(verified);

    expect((await bsb.contextFromSession(null)).auth.kind).toBe("none");
  });

  it("drops the cached session after deleting the account", async () => {
    const calls: string[] = [];

    const fetchMock = vi
      .spyOn(globalThis, "fetch")
      .mockImplementation((input, init) => {
        calls.push(`${init?.method ?? "GET"} ${String(input)}`);

        return Promise.resolve(Response.json({}));
      });

    const admin = createNext(betterSupabase, {
      env: { ...env, secretKey: "sb_secret_test" },
      cacheTags: false,
    });

    mocks.updateTag.mockReset();

    try {
      const result = await admin.deleteAccount(USER);
      expect(result).toMatchObject({
        ok: true,
        data: { userId: USER, removed: {} },
      });
      expect(calls).toEqual([
        `DELETE ${PROJECT_URL}/auth/v1/admin/users/${USER}`,
      ]);
      expect(mocks.updateTag).toHaveBeenCalledWith(sessionTag(USER));

      mocks.updateTag.mockReset();
      expect(await bsb.deleteAccount(USER)).toMatchObject({
        ok: false,
        error: { kind: "unexpected" },
      });
      expect(mocks.updateTag).not.toHaveBeenCalled();
    } finally {
      fetchMock.mockRestore();
    }
  });
});

describe("suspending accounts", () => {
  const betterSupabase = defineSupabase(schema);

  it("needs postgres to end sessions", async () => {
    const bsb = createNext(betterSupabase, {
      env: { ...env, secretKey: "sb_secret_test" },
      cacheTags: false,
    });

    expect(await bsb.endSessions(USER)).toMatchObject({
      ok: false,
      error: { kind: "invalid_request" },
    });
    expect(await bsb.suspendAccount(USER, { suspended: true })).toMatchObject({
      ok: false,
      error: { kind: "invalid_request" },
    });
  });

  it("drops the cached session after ending sessions or suspending", async () => {
    const calls: string[] = [];

    const fetchMock = vi
      .spyOn(globalThis, "fetch")
      .mockImplementation((input, init) => {
        calls.push(`${init?.method ?? "GET"} ${String(input)}`);

        return Promise.resolve(Response.json({}));
      });

    const queryRaw = vi.fn(async () => [{ ended: 2 }]);

    const bsb = createNext(betterSupabase, {
      env: { ...env, secretKey: "sb_secret_test" },
      cacheTags: false,
      postgres: { admin: { queryRaw } } as never,
    });

    mocks.updateTag.mockReset();

    try {
      expect(await bsb.endSessions(USER)).toMatchObject({
        ok: true,
        data: { userId: USER, ended: 2 },
      });
      expect(mocks.updateTag).toHaveBeenCalledWith(sessionTag(USER));
      mocks.updateTag.mockReset();
      expect(await bsb.suspendAccount(USER, { suspended: true })).toMatchObject(
        { ok: true, data: { userId: USER, suspended: true, ended: 0 } },
      );
      expect(calls).toEqual([`PUT ${PROJECT_URL}/auth/v1/admin/users/${USER}`]);
      expect(mocks.updateTag).toHaveBeenCalledWith(sessionTag(USER));
      expect(queryRaw).toHaveBeenCalledOnce();
    } finally {
      fetchMock.mockRestore();
    }
  });
});

describe("explicit tenants", () => {
  const TENANT = "00000000-0000-4000-8000-0000000000aa";
  const OTHER_TENANT = "00000000-0000-4000-8000-0000000000bb";

  const resolver = vi.fn(async (request: Request) => {
    await Promise.resolve();

    return request.headers.get("x-organization") ?? undefined;
  });

  const bsb = createNext(defineSupabase(schema), {
    env,
    cacheTags: false,
    auth: { jwks: signer.jwks },
    tenant: resolver,
  });

  beforeEach(async () => {
    resolver.mockClear();
    mocks.headers = new Headers({
      authorization: `Bearer ${await signer.sign({ sub: USER })}`,
    });
  });

  it("puts a tenant from route params where the resolver's goes", async () => {
    const resolved = await bsb.context(
      new Request("https://app.test/", {
        headers: {
          authorization: mocks.headers.get("authorization")!,
          "x-organization": TENANT,
        },
      }),
    );

    const explicit = await bsb.context({ tenant: TENANT });
    expect(explicit.db.$context).toEqual({
      ...resolved.db.$context,
      requestId: expect.any(String),
      memo: expect.any(Object),
    });
    expect(explicit.db.$context.tenant).toBe(TENANT);
    expect(resolver).toHaveBeenCalledOnce();
  });

  it("falls back to the resolver, even when an async one finds no tenant", async () => {
    expect((await bsb.context()).db.$context.tenant).toBeUndefined();
    mocks.headers.set("x-organization", OTHER_TENANT);
    expect((await bsb.context()).db.$context.tenant).toBe(OTHER_TENANT);
    expect((await bsb.context({ tenant: TENANT })).db.$context.tenant).toBe(
      TENANT,
    );
  });

  it("scopes bsb.cached() and actions to the tenant passed in", async () => {
    const ctx = await bsb.cached({ tenant: TENANT });
    expect(ctx.db.$context.tenant).toBe(TENANT);
    expect(ctx.session).toMatchObject({ kind: "user" });

    const action = bsb.action(
      {
        input: v.object({ organizationId: v.string() }),
        tenant: (input) => input.organizationId,
      },
      (_input, actionCtx) => actionCtx.db.$context.tenant ?? null,
    );

    expect(await action({ organizationId: TENANT })).toEqual({
      ok: true,
      data: TENANT,
      error: null,
    });

    const unscoped = bsb.action(
      {},
      (_input, actionCtx) => actionCtx.db.$context.tenant ?? null,
    );

    expect(await unscoped(undefined)).toMatchObject({ data: null });
  });
});

describe("cachedLife", () => {
  const now = 1_000_000_000_000;

  const user = (expiresAt: number | null) =>
    ({ kind: "user", expiresAt }) as never;

  it("floors stale at 300 seconds and leaves the token out unless asked", () => {
    expect(cachedLife({ kind: "none", reason: "none" }, "private")).toEqual({
      stale: 300,
    });
    expect(cachedLife(user(now / 1000 + 90), "private", {}, { now })).toEqual({
      stale: 300,
    });
    expect(
      cachedLife(user(now / 1000 + 90), "private", { stale: 900 }, { now }),
    ).toEqual({ stale: 900 });
  });

  it("caps stale to the token with capToToken, and drops its last 30 seconds", () => {
    const capped = { capToToken: true } as const;
    expect(
      cachedLife(user(now / 1000 + 90), "private", capped, { now }),
    ).toEqual({ stale: 90 });
    expect(
      cachedLife(user(now / 1000 + 20), "private", capped, { now }),
    ).toEqual({ stale: 0 });
    expect(cachedLife(user(null), "private", capped, { now })).toEqual({
      stale: 300,
    });
  });

  it("keeps a view a refresh or sign-in would change out of the App Shell", () => {
    expect(cachedLife({ kind: "none", reason: "expired" }, "private")).toEqual({
      stale: 0,
    });
    expect(
      cachedLife({ kind: "none", reason: "refresh_failed" }, "private"),
    ).toEqual({ stale: 0 });
    expect(
      cachedLife(
        {
          kind: "invalid",
          reason: "token",
          error: dbError("network", "JWKS unreachable"),
        },
        "private",
      ),
    ).toEqual({ stale: 0 });
    expect(cachedLife({ kind: "secret", keyName: "cron" }, "private")).toEqual({
      stale: 300,
    });
  });

  it("gives remote entries a revalidate and an expire", () => {
    expect(cachedLife(user(null), "remote")).toEqual({
      stale: 300,
      revalidate: 300,
      expire: 3600,
    });
    expect(cachedLife(user(null), "remote", { expire: 600 })).toEqual({
      stale: 300,
      revalidate: 300,
      expire: 600,
    });
  });

  it("warns once in development when stale leaves the App Shell or the prerender", () => {
    const warn = vi.fn<(message: string) => void>();
    cachedLife(user(null), "private", { stale: 120 }, { warn });
    cachedLife(user(null), "private", { stale: 120 }, { warn });
    cachedLife(user(null), "private", { stale: 10 }, { warn });
    cachedLife(user(null), "private", { stale: 300 }, { warn });
    expect(warn.mock.calls).toEqual([
      [expect.stringMatching(/below 300 seconds/)],
      [expect.stringMatching(/below 30 seconds/)],
    ]);
  });
});
