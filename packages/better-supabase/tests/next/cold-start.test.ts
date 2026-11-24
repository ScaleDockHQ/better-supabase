import { NextRequest } from "next/server.js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { coldRecord, recordCold } from "../../src/core/cold-start.ts";
import { createSupabase } from "../../src/core/define.ts";
import {
  formatColdStart,
  logColdStart,
  takeColdStart,
  timeFirst,
} from "../../src/next/cold-start.ts";
import { createNext } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({ headers: new Headers() }));

vi.mock(import("next/headers.js"), () => ({
  headers: () => Promise.resolve(mocks.headers),
  // SAFETY: the code under test reads only getAll() and set() from the jar.
  cookies: () =>
    Promise.resolve({ getAll: () => [], set: () => undefined } as never),
}));

vi.mock(import("next/cache.js"), () => ({
  updateTag() {},
  revalidateTag() {},
  cacheTag() {},
  cacheLife: () => undefined,
  io: () => Promise.resolve(),
}));

const KEY = Symbol.for("better-supabase.cold-start");
const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const USER = "11111111-1111-4111-8111-111111111111";

const signer = await createTestSigner();

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

describe("cold start report", () => {
  // SAFETY: the library keeps its cold-start record under KEY.
  const scope = globalThis as { [KEY]?: unknown };
  const saved = scope[KEY];
  let clock = 0;

  beforeEach(() => {
    delete scope[KEY];
    clock = 0;
    vi.spyOn(performance, "now").mockImplementation(() => clock);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    scope[KEY] = saved;
  });

  it("formats what ran and leaves out the rest", () => {
    expect(formatColdStart({})).toBe("");
    expect(
      formatColdStart({
        evalStart: 812.04,
        evalEnd: 930.5,
        create: 1.26,
        claims: 41,
      }),
    ).toBe("eval:118.5,ready:930.5,create:1.3,claims:41");
  });

  it("times only the first run", async () => {
    const slow = (ms: number) => async () => {
      await Promise.resolve();
      clock += ms;

      return ms;
    };

    expect(await timeFirst("claims", slow(45))).toBe(45);
    expect(await timeFirst("claims", slow(3))).toBe(3);
    expect(formatColdStart(coldRecord().timings)).toBe("claims:45");
  });

  it("records a step whose work throws", async () => {
    await expect(
      timeFirst("claims", async () => {
        await Promise.resolve();
        clock += 12;
        throw new Error("no token");
      }),
    ).rejects.toThrow("no token");

    expect(coldRecord().timings.claims).toBe(12);
  });

  it("hands out the record once per new step", () => {
    expect(takeColdStart()).toBeUndefined();

    recordCold("create", 2);
    expect(takeColdStart()).toBe("create:2");
    expect(takeColdStart()).toBeUndefined();

    recordCold("query", 70);
    expect(takeColdStart()).toBe("create:2,query:70");
  });

  it("logs one line when the first query returns, through the latest logger", () => {
    const first = vi.fn();
    const second = vi.fn();

    logColdStart(first);
    logColdStart(second);
    recordCold("claims", 40);
    recordCold("query", 70);
    recordCold("query", 9);

    expect(first).not.toHaveBeenCalled();
    expect(second.mock.calls).toEqual([["bsb.cold claims:40,query:70"]]);
  });
});

describe("debug.coldStart", () => {
  beforeEach(() => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async () =>
      Response.json([]),
    );
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("reports the first request's steps in the stats header and logs them once", async () => {
    const info = vi.fn();

    const bsb = createNext(
      createSupabase(schema, {
        logger: { debug() {}, info, warn() {}, error() {} },
      }),
      {
        env,
        cacheTags: false,
        auth: { jwks: signer.jwks },
        debug: { coldStart: true },
      },
    );

    const proxied = await bsb.proxy(
      new NextRequest("https://app.test/dashboard", {
        headers: { "sec-fetch-dest": "document" },
      }),
    );

    expect(proxied.headers.get("x-bsb-db-calls")).toMatch(
      /;cold=eval:[\d.]+,ready:[\d.]+,create:[\d.]+$/,
    );

    const id = proxied.headers.get("x-bsb-request-id")!;
    mocks.headers = new Headers({
      "x-bsb-request-id": id,
      authorization: `Bearer ${await signer.sign({ sub: USER })}`,
    });

    await bsb.getClaims();
    const ctx = await bsb.context();
    await ctx.db.customers.list();
    await ctx.db.notes.list();

    expect(info.mock.calls).toEqual([
      [
        expect.stringMatching(
          /^bsb\.cold eval:[\d.]+,ready:[\d.]+,create:[\d.]+,claims:[\d.]+,query:[\d.]+$/,
        ),
      ],
    ]);

    const stats = await bsb.debugRoute()(
      new Request(`https://app.test/api/bsb-stats?id=${id}`),
    );

    expect(stats.headers.get("x-bsb-db-calls")).toMatch(
      /^2;2;.*;cold=.*claims:[\d.]+,query:[\d.]+$/,
    );

    const again = await bsb.debugRoute()(
      new Request(`https://app.test/api/bsb-stats?id=${id}`),
    );

    expect(again.headers.get("x-bsb-db-calls")).not.toContain("cold=");
  });

  it("leaves the header as it was without the option", async () => {
    const bsb = createNext(createSupabase(schema), {
      env,
      cacheTags: false,
      auth: { jwks: signer.jwks },
      debug: { enabled: true },
    });

    const proxied = await bsb.proxy(
      new NextRequest("https://app.test/dashboard", {
        headers: { "sec-fetch-dest": "document" },
      }),
    );

    expect(proxied.headers.get("x-bsb-db-calls")).not.toContain("cold=");
  });
});
