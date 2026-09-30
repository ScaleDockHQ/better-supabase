import type * as ServerCore from "@supabase/server/core";
import type * as SupabaseJs from "@supabase/supabase-js";

import { beforeEach, describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../core/define.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createTestSigner } from "../testing/jwt.ts";
import { createNext, sessionStale, sessionTag } from "./index.ts";

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
  const sb = defineSupabase(schema);
  const next = createNext(sb, {
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
      const ctx = await next.context(
        new Request("https://app.test/", { headers: bearer }),
      );
      expect(ctx.auth.kind).toBe("user");
      if (island % 3 === 0) void ctx.db.customers;
    }
    expect(mocks.verifications).toBe(1);
    expect(mocks.clients).toBe(4);
  });

  it("caches per session with a stale time from the token", async () => {
    const exp = Math.floor(Date.now() / 1000) + 120;
    const token = await signer.sign({ sub: USER, expiresIn: 120 });
    mocks.headers = new Headers({ authorization: `Bearer ${token}` });
    const ctx = await next.cached({ life: { expire: 3600 } });
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

    next.invalidateSession(USER);
    expect(mocks.updateTag).toHaveBeenCalledWith(`bs:session:${USER}`);
  });

  it("builds a context from a session and its token", async () => {
    const token = await signer.sign({ sub: USER });
    const session = {
      kind: "user",
      user: { id: USER },
      claims: { sub: USER },
      expiresAt: null,
    } as never;
    const ctx = await next.serverFor(session, { token });
    expect(ctx.auth).toMatchObject({ kind: "user", user: { id: USER } });

    const foreign = await next.serverFor(session, {
      token: await signer.sign({ sub: OTHER }),
    });
    expect(foreign.auth).toMatchObject({
      kind: "invalid",
      error: { kind: "unauthorized" },
    });
    const anon = await next.serverFor(
      { kind: "anon", reason: "none" },
      {
        token: null,
      },
    );
    expect(anon.auth.kind).toBe("anon");
  });

  it("drops the cached session after deleting the account", async () => {
    const calls: string[] = [];
    const fetchMock = vi
      .spyOn(globalThis, "fetch")
      .mockImplementation((input, init) => {
        calls.push(`${init?.method ?? "GET"} ${String(input)}`);
        return Promise.resolve(Response.json({}));
      });
    const admin = createNext(sb, {
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
      expect(await next.deleteAccount(USER)).toMatchObject({
        ok: false,
        error: { kind: "unexpected" },
      });
      expect(mocks.updateTag).not.toHaveBeenCalled();
    } finally {
      fetchMock.mockRestore();
    }
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
    expect(sessionStale(user(now / 1000 + 5), {}, now)).toBe(30);
    expect(sessionStale(user(now / 1000 + 90), { min: 10, max: 60 }, now)).toBe(
      60,
    );
  });
});
