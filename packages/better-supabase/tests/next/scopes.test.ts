import type * as ServerCore from "@supabase/server/core";
import type * as SupabaseJs from "@supabase/supabase-js";

import * as v from "valibot";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { createNext, sessionStale, sessionTag } from "../../src/next/index.ts";
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
const OTHER = "22222222-2222-4222-8222-222222222222";
const signer = await createTestSigner();

describe("private-cache scopes", () => {
  const betterSupabase = defineSupabase(schema);
  const bs = createNext(betterSupabase, {
    env,
    cacheTags: false,
    auth: { jwks: signer.jwks as never },
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
    for (let island = 0; island < 12; island++) {
      const ctx = await bs.context(
        new Request("https://app.test/", { headers: bearer }),
      );
      expect(ctx.auth.kind).toBe("user");
      if (island % 3 === 0) void ctx.db.customers;
    }
    expect(mocks.verifications).toBe(1);
    // A user's ctx.db runs on a bare PostgREST client.
    expect(mocks.clients).toBe(0);
    const ctx = await bs.context(
      new Request("https://app.test/", { headers: bearer }),
    );
    expect(ctx.db.$client).toBe(ctx.supabase);
    expect(mocks.clients).toBe(1);
  });

  it("caches per session with a stale time from the token", async () => {
    const exp = Math.floor(Date.now() / 1000) + 120;
    const token = await signer.sign({ sub: USER, expiresIn: 120 });
    mocks.headers = new Headers({ authorization: `Bearer ${token}` });
    const ctx = await bs.cached({ life: { expire: 3600 } });
    expect(ctx.session).toMatchObject({ kind: "user", user: { id: USER } });
    expect(ctx.auth.kind).toBe("user");
    const [life] = mocks.cacheLife.mock.calls[0]! as [
      { stale: number; expire: number },
    ];
    expect(life.expire).toBe(3600);
    expect(life.stale).toBeGreaterThanOrEqual(
      exp - Math.floor(Date.now() / 1000) - 1,
    );
    expect(life.stale).toBeLessThanOrEqual(120);
    expect(mocks.cacheTag).toHaveBeenCalledWith(sessionTag(USER));

    bs.invalidateSession(USER);
    expect(mocks.updateTag).toHaveBeenCalledWith(`bs:session:${USER}`);
  });

  it("adds tags and caps stale with life.stale", async () => {
    const token = await signer.sign({ sub: USER, expiresIn: 3600 });
    mocks.headers = new Headers({ authorization: `Bearer ${token}` });
    const tags = [`authz:${USER}`, "organization:acme"];
    await bs.cached({ tags, life: { stale: 45 } });
    expect(mocks.cacheLife).toHaveBeenLastCalledWith({ stale: 45 });
    expect(mocks.cacheTag).toHaveBeenLastCalledWith(sessionTag(USER), ...tags);

    // A ceiling above the session's stale time leaves it alone.
    await bs.cached({ life: { stale: 900 } });
    expect(mocks.cacheLife).toHaveBeenLastCalledWith({ stale: 300 });

    mocks.headers = new Headers();
    await bs.cached({ tags: ["public:pricing"] });
    expect(mocks.cacheTag).toHaveBeenLastCalledWith("public:pricing");
    mocks.cacheTag.mockReset();
    await bs.cached();
    expect(mocks.cacheTag).not.toHaveBeenCalled();

    mocks.updateTag.mockReset();
    bs.invalidateSession(USER, { tags: [`authz:${USER}`] });
    expect(mocks.updateTag.mock.calls).toEqual([
      [sessionTag(USER)],
      [`authz:${USER}`],
    ]);
  });

  it("builds a context from a session and its token", async () => {
    const token = await signer.sign({ sub: USER });
    const session = {
      kind: "user",
      user: { id: USER },
      claims: { sub: USER },
      expiresAt: null,
    } as never;
    const ctx = await bs.contextForSession(session, { token });
    expect(ctx.auth).toMatchObject({ kind: "user", user: { id: USER } });

    const foreign = await bs.contextForSession(session, {
      token: await signer.sign({ sub: OTHER }),
    });
    expect(foreign.auth).toMatchObject({
      kind: "invalid",
      error: { kind: "unauthorized" },
    });
    const anon = await bs.contextForSession(
      { kind: "anon", reason: "none" },
      {
        token: null,
      },
    );
    expect(anon.auth.kind).toBe("anon");
    const service = await bs.contextForSession(
      { kind: "service", keyName: "cron" },
      { token: null },
    );
    expect(service.auth).toMatchObject({
      kind: "invalid",
      error: { kind: "unauthorized" },
    });
  });

  it("keeps the verification error of an expired token", async () => {
    const token = await signer.sign({ sub: USER, expiresIn: -60 });
    const session = {
      kind: "user",
      user: { id: USER },
      claims: { sub: USER },
      expiresAt: null,
    } as never;
    const ctx = await bs.contextForSession(session, { token });
    expect(ctx.auth.kind).toBe("invalid");
    expect(
      ctx.auth.kind === "invalid" ? ctx.auth.error.message : undefined,
    ).not.toMatch(/does not belong/);
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
      expect(await bs.deleteAccount(USER)).toMatchObject({
        ok: false,
        error: { kind: "unexpected" },
      });
      expect(mocks.updateTag).not.toHaveBeenCalled();
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
  const bs = createNext(defineSupabase(schema), {
    env,
    cacheTags: false,
    auth: { jwks: signer.jwks as never },
    tenant: resolver,
  });

  beforeEach(async () => {
    resolver.mockClear();
    mocks.headers = new Headers({
      authorization: `Bearer ${await signer.sign({ sub: USER })}`,
    });
  });

  it("puts a tenant from route params where the resolver's goes", async () => {
    const resolved = await bs.context(
      new Request("https://app.test/", {
        headers: {
          authorization: mocks.headers.get("authorization")!,
          "x-organization": TENANT,
        },
      }),
    );
    const explicit = await bs.context({ tenant: TENANT });
    expect(explicit.db.$context).toEqual(resolved.db.$context);
    expect(explicit.db.$context.tenant).toBe(TENANT);
    expect(resolver).toHaveBeenCalledTimes(1);
  });

  it("falls back to the resolver, even when an async one finds no tenant", async () => {
    expect((await bs.context()).db.$context.tenant).toBeUndefined();
    mocks.headers.set("x-organization", OTHER_TENANT);
    expect((await bs.context()).db.$context.tenant).toBe(OTHER_TENANT);
    expect((await bs.context({ tenant: TENANT })).db.$context.tenant).toBe(
      TENANT,
    );
  });

  it("scopes bs.cached() and actions to the tenant passed in", async () => {
    const ctx = await bs.cached({ tenant: TENANT });
    expect(ctx.db.$context.tenant).toBe(TENANT);
    expect(ctx.session).toMatchObject({ kind: "user" });

    const action = bs.action(
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
    const unscoped = bs.action(
      {},
      (_input, actionCtx) => actionCtx.db.$context.tenant ?? null,
    );
    expect(await unscoped(undefined)).toMatchObject({ data: null });
  });
});

describe("sessionStale", () => {
  const now = 1_000_000_000_000;
  const user = (expiresAt: number | null) =>
    ({ kind: "user", expiresAt }) as never;

  it("stays within min and max and never outlives the token", () => {
    expect(sessionStale({ kind: "anon", reason: "none" })).toBe(300);
    expect(sessionStale(user(null))).toBe(300);
    expect(sessionStale(user(now / 1000 + 3600), {}, now)).toBe(300);
    expect(sessionStale(user(now / 1000 + 90), {}, now)).toBe(90);
    expect(sessionStale(user(now / 1000 + 90), { min: 10, max: 60 }, now)).toBe(
      60,
    );
  });

  it("keeps a view of a token in its last seconds out of prefetches", () => {
    expect(sessionStale(user(now / 1000 + 5), {}, now)).toBe(0);
    expect(sessionStale(user(now / 1000 - 5), {}, now)).toBe(0);
    expect(sessionStale(user(now / 1000 + 45), { min: 10 }, now)).toBe(45);
    // The client router keeps an entry for 30 seconds, so `min` never goes lower.
    expect(sessionStale(user(now / 1000 + 20), { min: 10 }, now)).toBe(0);
  });

  it("keeps a signed-out view that a refresh or sign-in would change out of the App Shell", () => {
    expect(sessionStale({ kind: "anon", reason: "expired" })).toBe(0);
    expect(sessionStale({ kind: "anon", reason: "refresh_failed" })).toBe(0);
    expect(
      sessionStale({
        kind: "invalid",
        reason: "token",
        error: dbError("network", "JWKS unreachable"),
      }),
    ).toBe(0);
    expect(sessionStale({ kind: "anon", reason: "signed_out" })).toBe(300);
    expect(sessionStale({ kind: "service", keyName: "cron" })).toBe(300);
  });
});
