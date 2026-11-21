import { describe, expect, it, vi } from "vitest";

import type { CacheTarget } from "../../src/core/cache.ts";

import { cacheRoute } from "../../src/core/cache-route.ts";
import { memoryCache } from "../../src/core/cache.ts";
import { createSupabase } from "../../src/core/define.ts";
import { signWebhook } from "../../src/core/signatures.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = createSupabase(schema);
const SECRET = `whsec_${btoa("cache-route-secret-0123456789")}`;
const BEARER = "bearer-secret";
const ROUTE_URL = "https://app.test/api/cache";

function setup(options: Partial<Parameters<typeof cacheRoute>[0]> = {}) {
  const cache = memoryCache();

  const route = cacheRoute({
    betterSupabase,
    caches: [cache],
    secret: SECRET,
    bearer: BEARER,
    ...options,
  });

  return { cache, route };
}

function withBearer(body: unknown, token = BEARER): Request {
  return new Request(ROUTE_URL, {
    method: "POST",
    headers: { authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
}

async function signed(body: unknown, secret = SECRET): Promise<Request> {
  const text = JSON.stringify(body);

  return new Request(ROUTE_URL, {
    method: "POST",
    headers: await signWebhook(secret, { id: "msg_1", body: text }),
    body: text,
  });
}

describe("cacheRoute", () => {
  it("needs a secret or a bearer", () => {
    expect(() => cacheRoute({ betterSupabase, caches: [] })).toThrow(
      "needs a secret",
    );
  });

  it("answers 405 to other methods", async () => {
    const { route } = setup();
    const response = await route(new Request(ROUTE_URL));
    expect(response.status).toBe(405);
  });

  it("refuses a request without a signature or the bearer", async () => {
    const { cache, route } = setup();

    const none = await route(
      new Request(ROUTE_URL, { method: "POST", body: "{}" }),
    );

    const wrong = await route(withBearer({ table: "notes" }, "nope"));

    expect(none.status).toBe(401);
    expect(wrong.status).toBe(401);
    expect(cache.invalidated).toEqual([]);
  });

  it("refuses a signature made with another secret", async () => {
    const { cache, route } = setup({ bearer: undefined });
    const other = `whsec_${btoa("another-secret-0123456789-abcdef")}`;
    const response = await route(await signed({ table: "notes" }, other));

    expect(response.status).toBe(401);
    expect(cache.invalidated).toEqual([]);
  });

  it("does not take the bearer when only a secret is set", async () => {
    const { route } = setup({ bearer: undefined });
    const response = await route(withBearer({ table: "notes" }));
    expect(response.status).toBe(401);
  });

  it("expires the table, ids and tenant of a signed envelope", async () => {
    const { cache, route } = setup();

    const response = await route(
      await signed({
        schema: "public",
        table: "notes",
        op: "UPDATE",
        ids: ["n1", "n2"],
        tenants: ["org-1"],
      }),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ invalidated: 1 });
    expect(cache.invalidated).toEqual<CacheTarget[]>([
      { table: "notes", tables: ["notes"], ids: ["n1", "n2"], tenant: "org-1" },
    ]);
  });

  it("makes one target per tenant and expires every tenant for a null one", async () => {
    const { cache, route } = setup();

    await route(
      withBearer({
        table: "notes",
        op: "INSERT",
        ids: ["n1"],
        tenants: ["org-1", null],
      }),
    );

    expect(cache.invalidated.map((target) => target.tenant)).toEqual([
      "org-1",
      undefined,
    ]);
  });

  it("finds a table by its database name and joins a composite key", async () => {
    const { cache, route } = setup();

    await route(
      withBearer({
        schema: "public",
        table: "customer_tags",
        op: "INSERT",
        ids: ["c1,t1"],
        tenants: [],
      }),
    );

    expect(cache.invalidated).toEqual<CacheTarget[]>([
      { table: "customerTags", tables: ["customerTags"], ids: ["c1,t1"] },
    ]);
  });

  it("expires the tables a delete cascades to", async () => {
    const { cache, route } = setup();

    await route(
      withBearer({
        table: "customers",
        op: "DELETE",
        ids: ["c1"],
        tenants: [],
      }),
    );

    const [target] = cache.invalidated;
    expect(target?.tables).toContain("customers");
    expect(target?.tables.length).toBeGreaterThan(1);
  });

  it("reads a Supabase Database Webhook, with ids and the tenant from the row", async () => {
    const { cache, route } = setup();

    await route(
      withBearer({
        type: "UPDATE",
        table: "customer_tags",
        schema: "public",
        record: { customer_id: "c1", tag_id: "t1", organization_id: "org-1" },
        old_record: {
          customer_id: "c1",
          tag_id: "t1",
          organization_id: "org-2",
        },
      }),
    );

    expect(cache.invalidated).toEqual<CacheTarget[]>([
      {
        table: "customerTags",
        tables: ["customerTags"],
        ids: ["c1,t1"],
        tenant: "org-1",
      },
      {
        table: "customerTags",
        tables: ["customerTags"],
        ids: ["c1,t1"],
        tenant: "org-2",
      },
    ]);
  });

  it("reads a CloudEvent from the outbox and a batch", async () => {
    const { cache, route } = setup();

    await route(
      await signed([
        {
          type: "bsb.cache",
          data: { table: "notes", ids: ["a"], tenant: "o" },
        },
        { table: "tags", ids: ["b"] },
      ]),
    );

    expect(cache.invalidated.map((target) => target.table)).toEqual([
      "notes",
      "tags",
    ]);
    expect(cache.invalidated[0]?.tenant).toBe("o");
  });

  it("answers 200 and expires nothing for a table it doesn't know", async () => {
    const { cache, route } = setup();
    const response = await route(withBearer({ table: "audit_log", ids: [] }));

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ invalidated: 0 });
    expect(cache.invalidated).toEqual([]);
  });

  it("answers 400 to a body that isn't JSON", async () => {
    const { route } = setup();

    const response = await route(
      new Request(ROUTE_URL, {
        method: "POST",
        headers: { authorization: `Bearer ${BEARER}` },
        body: "nope",
      }),
    );

    expect(response.status).toBe(400);
  });

  it("answers 502 when an adapter throws, so the sender retries", async () => {
    const failing = {
      name: "failing",
      invalidate: vi.fn<() => Promise<void>>(() =>
        Promise.reject(new Error("429")),
      ),
    };

    const { route } = setup({ caches: [failing] });
    const response = await route(withBearer({ table: "notes", ids: ["a"] }));

    expect(response.status).toBe(502);
    expect(failing.invalidate).toHaveBeenCalledOnce();
  });

  it("refuses a replayed delivery when seen reports it", async () => {
    const { cache, route } = setup({ verify: { seen: () => false } });
    const first = await route(await signed({ table: "notes" }));

    const replay = setup({ verify: { seen: () => true } });
    const second = await replay.route(await signed({ table: "notes" }));

    expect(first.status).toBe(200);
    expect(second.status).toBe(409);
    expect(replay.cache.invalidated).toEqual([]);
    expect(cache.invalidated).toHaveLength(1);
  });
});
