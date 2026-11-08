import type * as ServerCore from "@supabase/server/core";

import { beforeEach, describe, expect, it, vi } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { defineReadSet } from "../../src/core/read-set.ts";
import { createNext } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({ headers: new Headers(), verifications: 0 }));

vi.mock(import("next/headers.js"), () => ({
  // SAFETY: the code under test reads only getAll from the cookie jar.
  cookies: () => Promise.resolve({ getAll: () => [] } as never),
  headers: () => Promise.resolve(mocks.headers as never),
}));

vi.mock(import("next/cache.js"), () => ({
  cacheLife: vi.fn(),
  cacheTag: vi.fn(),
  updateTag: vi.fn(),
  revalidateTag: vi.fn(),
  io: () => Promise.resolve(),
}));

vi.mock(import("@supabase/server/core"), async (original) => {
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

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const USER = "11111111-1111-4111-8111-111111111111";
const CUSTOMER = "22222222-2222-4222-8222-222222222222";
const signer = await createTestSigner();

const betterSupabase = createSupabase(schema);

// The customer hub of CentraKit's customer page: the customer list, its
// notes and tags, behind one permission, in one call.
const customersHub = defineReadSet(
  betterSupabase,
  "customers_hub",
  { params: { search: "text" } },
  (s, p, auth) => ({
    customers: s.when(
      auth.can("customer.read"),
      s.customers.list({
        select: ["id", "name"],
        where: { name: { contains: p.search } },
        limit: 20,
      }),
    ),
    notes: s.when(auth.can("customer.read"), s.notes.count()),
    tags: s.when(auth.can("customer.read"), s.tags.list({ select: ["id"] })),
  }),
);

// One customer tab: the customer with its notes, behind the same permission.
const customerDetail = defineReadSet(
  betterSupabase,
  "customer_detail",
  { params: { customerId: "uuid" } },
  (s, p, auth) => ({
    customer: s.when(
      auth.can("customer.read"),
      s.customers.get(p.customerId, { include: { notes: true } }),
    ),
  }),
);

describe("customer read sets over PostgREST", () => {
  const bsb = createNext(betterSupabase, {
    env,
    cacheTags: false,
    auth: { jwks: signer.jwks },
  });

  let requests: { path: string; apikey: string | null }[] = [];

  beforeEach(async () => {
    requests = [];
    mocks.verifications = 0;

    mocks.headers = new Headers({
      authorization: `Bearer ${await signer.sign({ sub: USER })}`,
    });

    vi.spyOn(globalThis, "fetch").mockImplementation((input, init) => {
      const url = new URL(input instanceof Request ? input.url : String(input));

      requests.push({
        path: url.pathname,
        apikey: new Headers(init?.headers).get("apikey"),
      });

      return Promise.resolve(
        Response.json(
          url.pathname.endsWith("rs_customers_hub")
            ? {
                customers: { rows: [{ id: CUSTOMER, name: "Acme" }], count: 1 },
                notes: { rows: [], count: 3 },
                tags: { rows: [{ id: "t1" }], count: 1 },
              }
            : { customer: { rows: [{ id: CUSTOMER, notes: [] }], count: 1 } },
        ),
      );
    });
  });

  it("loads the hub in one call and one wave, as the user", async () => {
    const ctx = await bsb.context(
      new Request("https://app.test/customers", { headers: mocks.headers }),
    );

    const hub = await ctx.db.$many(customersHub, { search: "ac" });

    expect(hub.ok && hub.data.notes).toBe(3);
    expect(requests.map((request) => request.path)).toEqual([
      "/rest/v1/rpc/rs_customers_hub",
    ]);
    expect(ctx.stats()).toMatchObject({ calls: 1, waves: 1, adminCalls: 0 });
  });

  it("loads a detail tab in one call", async () => {
    const ctx = await bsb.context(
      new Request("https://app.test/customers/c1", { headers: mocks.headers }),
    );

    const detail = await ctx.db.$many(customerDetail, { customerId: CUSTOMER });

    expect(detail.ok).toBe(true);
    expect(requests).toHaveLength(1);
    expect(ctx.stats()).toMatchObject({ calls: 1, waves: 1, adminCalls: 0 });
  });

  it("verifies the token once, and not again in a nested scope that takes the session", async () => {
    const handle = await bsb.sessionHandle();
    const verified = mocks.verifications;

    expect(verified).toBe(1);

    const nested = await bsb.cached({ session: handle });
    const hub = await nested.db.$many(customersHub, { search: "" });

    expect(hub.ok).toBe(true);
    expect(mocks.verifications - verified).toBe(0);
  });

  it("makes no admin call on a cold instance", async () => {
    // No secret key is configured: a service-role call has nothing to send.
    const ctx = await bsb.context(
      new Request("https://app.test/customers", { headers: mocks.headers }),
    );

    await ctx.db.$many(customersHub, { search: "" });
    await ctx.db.$many(customerDetail, { customerId: CUSTOMER });

    expect(ctx.stats().adminCalls).toBe(0);
    expect(requests.every((request) => request.apikey !== null)).toBe(true);
    expect(
      requests.some((request) => request.apikey?.startsWith("sb_secret")),
    ).toBe(false);
  });
});
