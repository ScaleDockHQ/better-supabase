import type { MockInstance } from "vitest";

import { NextRequest } from "next/server.js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
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

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const USER = "11111111-1111-4111-8111-111111111111";

const signer = await createTestSigner();

describe("request stats in cache scopes", () => {
  let rest: MockInstance<typeof fetch>;

  beforeEach(() => {
    rest = vi
      .spyOn(globalThis, "fetch")
      .mockImplementation(async () => Response.json([]));
  });

  afterEach(() => {
    rest.mockRestore();
  });

  const debugged = () =>
    createNext(createSupabase(schema), {
      env: {
        url: PROJECT_URL,
        publishableKey: "sb_publishable_test",
        jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
      },
      cacheTags: false,
      auth: { jwks: signer.jwks },
      debug: { enabled: true },
    });

  const statsOf = async (
    bsb: ReturnType<typeof debugged>,
    id: string,
  ): Promise<unknown> =>
    (
      await bsb.debugRoute()(
        new Request(`https://app.test/api/bsb-stats?id=${id}`),
      )
    ).json();

  const signedIn = async (bsb: ReturnType<typeof debugged>) => {
    const proxied = await bsb.proxy(
      new NextRequest("https://app.test/dashboard", {
        headers: { "sec-fetch-dest": "document" },
      }),
    );

    const id = proxied.headers.get("x-bsb-request-id")!;

    mocks.headers = new Headers({
      "x-bsb-request-id": id,
      authorization: `Bearer ${await signer.sign({ sub: USER })}`,
    });

    return id;
  };

  it("records the raw client's data calls in a private cache fill, not its auth calls", async () => {
    const bsb = debugged();
    const id = await signedIn(bsb);

    const ctx = await bsb.cached();
    await ctx.db.customers.list();
    await ctx.supabase.from("customers").select("id");
    await ctx.supabase.rpc("customers_by_status");
    await ctx.supabase.auth.getUser().catch(() => undefined);

    expect(await statsOf(bsb, id)).toMatchObject({
      calls: 3,
      tables: ["customers", "customers_by_status()"],
    });
  });

  it("records a remote cache fill on the request that started it", async () => {
    const bsb = debugged();
    const id = await signedIn(bsb);

    const read = bsb.remote(async (key) => {
      const ctx = await bsb.cached({ scope: "remote", key });

      return ctx.db.customers.list();
    });

    await read();

    expect(await statsOf(bsb, id)).toMatchObject({
      calls: 1,
      tables: ["customers"],
    });
  });
});
