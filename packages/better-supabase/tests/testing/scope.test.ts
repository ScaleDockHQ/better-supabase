import { afterEach, describe, expect, it, vi } from "vitest";

import type { BetterPostgres } from "../../src/postgres/pool.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { asUser } from "../../src/testing/as-user.ts";
import { scopedSeed, withRollback } from "../../src/testing/scope.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

afterEach(() => {
  vi.unstubAllGlobals();
});

/** A pool whose transactions run the callback and record the claims. */
function fakePostgres(transactions: unknown[]): BetterPostgres {
  const client = { query: () => Promise.resolve({ rows: [], rowCount: 0 }) };

  // SAFETY: the test only needs the parts of the pool that asUser and withRollback call.
  return {
    asUser: () => client,
    transaction: async (
      fn: (client: unknown) => Promise<unknown>,
      options: unknown,
    ) => {
      transactions.push(options);

      return fn(client);
    },
  } as never;
}

/** PostgREST that echoes inserted rows and records every request. */
function stubRest(calls: { method: string; url: string }[]): void {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = new Request(input, init);
      calls.push({ method: request.method, url: request.url });

      if (request.method === "POST") {
        const body: Record<string, unknown> = await request.json();

        return Response.json([{ id: crypto.randomUUID(), ...body }], {
          status: 201,
        });
      }

      return new Response(null, {
        status: 204,
        headers: { "content-range": "*/1" },
      });
    }),
  );
}

describe("withRollback", () => {
  it("explains that it needs a user with postgres", async () => {
    const user = await asUser(
      betterSupabase,
      { sub: "11111111-1111-4111-8111-111111111111" },
      { publishableKey: "sb_publishable_test", alg: "HS256" },
    );

    await expect(withRollback(user, () => Promise.resolve(1))).rejects.toThrow(
      /asUser\(betterSupabase, claims, \{ postgres \}\)/,
    );
  });
});

describe("scopedSeed", () => {
  it("needs a service-role key", async () => {
    const saved = process.env["SUPABASE_SECRET_KEY"];
    delete process.env["SUPABASE_SECRET_KEY"];

    try {
      await expect(
        scopedSeed(betterSupabase, () => ({}), { stack: {} }),
      ).rejects.toThrow(/SUPABASE_SECRET_KEY/);
    } finally {
      if (saved !== undefined) {
        process.env["SUPABASE_SECRET_KEY"] = saved;
      }
    }
  });
});

describe("withRollback over a pool", () => {
  it("returns the value and rolls the transaction back", async () => {
    const transactions: unknown[] = [];

    const user = await asUser(
      betterSupabase,
      { sub: "11111111-1111-4111-8111-111111111111" },
      {
        publishableKey: "sb_publishable_test",
        alg: "HS256",
        postgres: fakePostgres(transactions),
      },
    );

    const value = await withRollback(user, (db) => {
      expect(db.customers).toBeDefined();

      return Promise.resolve(42);
    });

    expect(value).toBe(42);
    expect(transactions).toEqual([
      { claims: expect.objectContaining({ sub: user.claims.sub }) },
    ]);
  });

  it("rethrows what the callback throws", async () => {
    const user = await asUser(
      betterSupabase,
      { sub: "11111111-1111-4111-8111-111111111111" },
      {
        publishableKey: "sb_publishable_test",
        alg: "HS256",
        postgres: fakePostgres([]),
      },
    );

    await expect(
      withRollback(user, () => Promise.reject(new Error("boom"))),
    ).rejects.toThrow("boom");
  });
});

describe("scopedSeed over PostgREST", () => {
  const stack = { url: "http://127.0.0.1:54321", secretKey: "sb_secret_test" };

  const tenant = {
    table: "organizations",
    row: (id: string) => ({ id, name: id, slug: id }),
  } as const;

  it("inserts the tenant and fixtures, then deletes them in reverse", async () => {
    const calls: { method: string; url: string }[] = [];
    stubRest(calls);

    const scope = await scopedSeed(
      betterSupabase,
      ({ tenant: id }) => ({
        customers: { first: { organizationId: id, name: "first" } },
      }),
      { tenant, stack },
    );

    expect(scope.tenant).toMatch(/^[0-9a-f-]{36}$/);
    expect(scope.rows.customers.first.name).toBe("first");
    expect(calls.map((call) => call.method)).toEqual(["POST", "POST"]);

    await scope.cleanup();

    const deletes = calls.filter((call) => call.method === "DELETE");

    expect(deletes.map((call) => new URL(call.url).pathname)).toEqual([
      "/rest/v1/customers",
      "/rest/v1/organizations",
    ]);
  });

  it("deletes what it inserted when a fixture fails", async () => {
    const calls: { method: string; url: string }[] = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
        const request = new Request(input, init);
        calls.push({ method: request.method, url: request.url });

        if (new URL(request.url).pathname.endsWith("/customers")) {
          return Response.json({ message: "nope" }, { status: 400 });
        }

        if (request.method === "POST") {
          const body: unknown = await request.json();

          return Response.json([body], { status: 201 });
        }

        return new Response(null, { status: 204 });
      }),
    );

    await expect(
      scopedSeed(
        betterSupabase,
        ({ tenant: id }) => ({
          customers: { first: { organizationId: id, name: "first" } },
        }),
        { tenant, stack },
      ),
    ).rejects.toThrow(/scopedSeed customers/);

    expect(calls.filter((call) => call.method === "DELETE")).toHaveLength(1);
  });

  it("disposes with await using", async () => {
    const calls: { method: string; url: string }[] = [];
    stubRest(calls);

    {
      await using scope = await scopedSeed(betterSupabase, () => ({}), {
        stack,
      });

      expect(scope.rows).toEqual({});
    }

    expect(calls).toEqual([]);
  });
});
