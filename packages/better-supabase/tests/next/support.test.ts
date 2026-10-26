import { beforeEach, describe, expect, it, vi } from "vitest";

import type { BetterPostgres, SqlClaims } from "../../src/postgres/pool.ts";

import { supportOf } from "../../src/auth/support-view.ts";
import { defineSupabase } from "../../src/core/define.ts";
import {
  createNext,
  sessionTag,
  supportSessions,
  supportTag,
} from "../../src/next/index.ts";
import { postgresExecutor } from "../../src/postgres/executor.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { memorySupportStore } from "../fixtures/support-store.ts";

const mocks = vi.hoisted(() => ({
  headers: new Headers(),
  updateTag: vi.fn<(tag: string) => void>(),
  cacheTag: vi.fn<(...tags: string[]) => void>(),
  cacheLife: vi.fn<(life: unknown) => void>(),
  setCookie: vi.fn<(name: string, value: string, options: unknown) => void>(),
  deleteCookie: vi.fn<(options: unknown) => void>(),
}));

vi.mock("next/headers.js", () => ({
  headers: () => Promise.resolve(mocks.headers),
  cookies: () =>
    Promise.resolve({
      set: mocks.setCookie,
      delete: mocks.deleteCookie,
      getAll: () =>
        (mocks.headers.get("cookie") ?? "")
          .split("; ")
          .filter(Boolean)
          .map((pair) => ({
            name: pair.slice(0, pair.indexOf("=")),
            value: decodeURIComponent(pair.slice(pair.indexOf("=") + 1)),
          })),
    }),
}));

vi.mock("next/cache.js", () => ({
  updateTag: mocks.updateTag,
  revalidateTag: vi.fn(),
  cacheTag: mocks.cacheTag,
  cacheLife: mocks.cacheLife,
  io: () => Promise.resolve(),
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const ADMIN = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const TARGET = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const signer = await createTestSigner();
const token = await signer.sign({ sub: ADMIN, role: "authenticated" });

function setup() {
  const fake = fakeSql();
  const claims: SqlClaims[] = [];

  // SAFETY: the server only calls executorFor; the executor only calls queryRaw.
  const postgres = {
    admin: fake.sql,
    executorFor: (value: SqlClaims) => {
      claims.push(value);

      return postgresExecutor(fake.sql);
    },
  } as unknown as BetterPostgres;

  const store = memorySupportStore();

  const bsb = createNext(defineSupabase(schema), {
    env,
    auth: { jwks: signer.jwks },
    postgres,
    support: supportSessions({
      store,
      cookie: { secure: false },
      authorize: () => true,
      policy: { approval: "none" },
    }),
  });

  return { bsb, store, claims };
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.headers = new Headers({ authorization: `Bearer ${token}` });
});

describe("support sessions in Next.js", () => {
  it("starts, renders as the target and stops", async () => {
    const { bsb, claims } = setup();

    const started = await bsb.startSupport({
      targetUserId: TARGET,
      reason: "ticket 4",
    });

    expect(started.ok).toBe(true);
    const id = started.data!.sessionId;
    expect(started.data).toMatchObject({
      targetUserId: TARGET,
      readOnly: true,
    });
    expect(mocks.setCookie).toHaveBeenCalledWith("bsb-support", id, {
      httpOnly: true,
      sameSite: "lax",
      path: "/",
      secure: false,
      maxAge: expect.any(Number) as number,
    });
    expect(mocks.updateTag).toHaveBeenCalledWith(sessionTag(ADMIN));

    mocks.headers.set("cookie", `bsb-support=${id}`);
    const view = await bsb.session();
    expect(view.kind === "user" && view.user.id).toBe(TARGET);
    expect(supportOf(view)).toMatchObject({ sessionId: id, adminId: ADMIN });
    const cached = await bsb.cached();
    expect(mocks.cacheTag).toHaveBeenCalledWith(
      sessionTag(TARGET),
      supportTag(id),
    );
    await cached.db.customers.list({ select: ["id"] }).orThrow();
    expect(claims[0]).toMatchObject({ sub: TARGET, act: { sub: ADMIN } });

    const action = bsb.action(
      {},
      (_input, ctx) => ctx.auth.kind === "user" && ctx.auth.user.id,
    );

    expect((await action(undefined)).data).toBe(TARGET);

    const stopped = await bsb.stopSupport();
    expect(stopped).toEqual({ ok: true, data: { ended: true }, error: null });
    expect(mocks.deleteCookie).toHaveBeenCalledWith({
      name: "bsb-support",
      path: "/",
    });
    expect(mocks.updateTag).toHaveBeenCalledWith(supportTag(id));
  });

  it("returns the refusal as an ActionResult", async () => {
    const { bsb } = setup();
    const refused = await bsb.startSupport({ targetUserId: TARGET });
    expect(refused.ok).toBe(false);
    expect(refused.error?.code).toBe("SUPPORT_REASON_REQUIRED");
    expect(mocks.setCookie).not.toHaveBeenCalled();
  });

  it("stops without a cookie, and reports a store failure", async () => {
    const { bsb, store } = setup();
    expect(await bsb.stopSupport()).toEqual({
      ok: true,
      data: { ended: false },
      error: null,
    });
    store.get = () => Promise.reject(new Error("down"));
    mocks.headers.set("cookie", "bsb-support=x");
    const failed = await bsb.stopSupport();
    expect(failed.ok).toBe(false);
  });
});
