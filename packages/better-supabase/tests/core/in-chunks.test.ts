import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import type { SchemaMeta } from "../../src/schema/types.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

const ids = Array.from(
  { length: 300 },
  (_, index) => `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
);

function listOf(param: string | null): string[] {
  return (param ?? "").replaceAll(/^in\.\(|\)$/g, "").split(",");
}

describe("oversized in lists", () => {
  const betterSupabase = defineSupabase(schema, { urlLengthLimit: 4000 });

  it("splits an unpaginated read and merges the rows", async () => {
    const { client, requests } = capturingClient((request) => ({
      body: listOf(request.params.get("id")).map((id) => ({ id })),
    }));
    const rows = await betterSupabase
      .connect(client)
      .customers.findMany({
        select: ["id"],
        where: { id: { in: ids }, status: "active" },
        orderBy: { id: "desc" },
      })
      .orThrow();
    expect(requests.length).toBeGreaterThan(1);
    for (const request of requests) {
      expect(request.params.get("status")).toBe("eq.active");
      expect(request.params.toString().length).toBeLessThanOrEqual(4000);
    }
    expect(
      requests.flatMap((request) => listOf(request.params.get("id"))),
    ).toEqual(ids);
    expect(rows.map((row) => row.id)).toEqual([...ids].reverse());
  });

  it("selects an unselected order column for the sort and removes it", async () => {
    const { client, requests } = capturingClient((request) => ({
      body: listOf(request.params.get("id")).map((id, index) => ({
        id,
        _bs_order0: `2026-01-01T00:00:${String(59 - (index % 60)).padStart(2, "0")}+00:00`,
      })),
    }));
    const rows = await betterSupabase
      .connect(client)
      .customers.findMany({
        select: ["id"],
        where: { id: { in: ids } },
        orderBy: { createdAt: "asc" },
      })
      .orThrow();
    expect(requests.length).toBeGreaterThan(1);
    for (const request of requests) {
      expect(request.params.get("select")).toBe("id,_bs_order0:created_at");
      expect(request.params.toString().length).toBeLessThanOrEqual(4000);
    }
    expect(rows).toHaveLength(ids.length);
    expect(rows.every((row) => Object.keys(row).join() === "id")).toBe(true);
  });

  it("orders by the primary key without selecting it", async () => {
    const { client } = capturingClient((request) => ({
      body: listOf(request.params.get("id"))
        .map((id) => ({ name: id, _bs_order0: id }))
        .reverse(),
    }));
    const rows = await betterSupabase
      .connect(client)
      .customers.findMany({ select: ["name"], where: { id: { in: ids } } })
      .orThrow();
    expect(rows.map((row) => row.name)).toEqual(ids);
  });

  it("sends each value once when the list repeats values", async () => {
    const { client, requests } = capturingClient((request) => ({
      body: listOf(request.params.get("id")).map((id) => ({ id })),
    }));
    const rows = await betterSupabase
      .connect(client)
      .customers.findMany({
        select: ["id"],
        where: { id: { in: [...ids, ...ids] } },
      })
      .orThrow();
    const sent = requests.flatMap((request) =>
      listOf(request.params.get("id")),
    );
    expect(sent).toEqual(ids);
    expect(rows).toHaveLength(ids.length);
  });

  it("orders times by instant across offsets", async () => {
    const times = [
      "2026-01-01T02:00:00+02:00",
      "2026-01-01T00:30:00+00:00",
      "2026-01-01T00:00:00.000001+00:00",
      "2026-01-01T00:00:00+00:00",
    ];
    const { client } = capturingClient((request) => ({
      body: listOf(request.params.get("id")).map((id, index) => ({
        id,
        createdAt: times[index % times.length],
      })),
    }));
    const rows = await betterSupabase
      .connect(client)
      .customers.findMany({
        select: ["id", "createdAt"],
        where: { id: { in: ids } },
        orderBy: { createdAt: "asc" },
      })
      .orThrow();
    const order = [...new Set(rows.map((row) => row.createdAt))];
    expect(order.slice(2)).toEqual([
      "2026-01-01T00:00:00.000001+00:00",
      "2026-01-01T00:30:00+00:00",
    ]);
    expect(order.slice(0, 2).sort()).toEqual([
      "2026-01-01T00:00:00+00:00",
      "2026-01-01T02:00:00+02:00",
    ]);
  });

  it("runs at most four chunks at once", async () => {
    let inFlight = 0;
    let peak = 0;
    let calls = 0;
    const client = createClient(
      "http://localhost:54321",
      "sb_publishable_test",
      {
        auth: { persistSession: false, autoRefreshToken: false },
        global: {
          fetch: async (input) => {
            calls += 1;
            inFlight += 1;
            peak = Math.max(peak, inFlight);
            await new Promise((resolve) => {
              setTimeout(resolve, 2);
            });
            inFlight -= 1;
            const url = new URL(String(input));
            return Response.json(
              listOf(url.searchParams.get("id")).map((id) => ({ id })),
            );
          },
        },
      },
    );
    const many = Array.from(
      { length: 1500 },
      (_, index) =>
        `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
    );
    const rows = await defineSupabase(schema, { urlLengthLimit: 2000 })
      .connect(client)
      .customers.findMany({ select: ["id"], where: { id: { in: many } } })
      .orThrow();
    expect(rows).toHaveLength(many.length);
    expect(calls).toBeGreaterThan(4);
    expect(peak).toBe(4);
  });

  it("keeps a read that fits in one request", async () => {
    const { client, requests } = capturingClient();
    await betterSupabase
      .connect(client)
      .customers.findMany({ where: { id: { in: ids.slice(0, 10) } } })
      .orThrow();
    expect(requests).toHaveLength(1);
  });

  it("sorts merged rows with nulls where Postgres puts them", async () => {
    const { client } = capturingClient((request) => ({
      body: listOf(request.params.get("id")).map((id, index) => ({
        id,
        createdAt:
          index % 50 === 0
            ? null
            : `2026-01-01T00:00:${String(index % 60).padStart(2, "0")}+00:00`,
      })),
    }));
    const rows = await betterSupabase
      .connect(client)
      .customers.findMany({
        select: ["id", "createdAt"],
        where: { id: { in: ids } },
        orderBy: [{ createdAt: "asc" }, { id: "asc" }],
      })
      .orThrow();
    const times: unknown[] = rows.map((row) => row.createdAt);
    const firstNull = times.indexOf(null);
    expect(times.slice(firstNull).every((time) => time === null)).toBe(true);
    const present = times.slice(0, firstNull);
    expect(present).toEqual(
      [...present].sort((a, b) => String(a).localeCompare(String(b))),
    );
  });

  it.each([
    [
      "a paginated read",
      { where: { id: { in: ids } }, limit: 10 },
      "limit, offset, count or single row",
    ],
    [
      "an order on text",
      {
        where: { id: { in: ids } },
        orderBy: { name: "asc" },
        select: ["id", "name"],
      },
      'order on "name"',
    ],
    [
      "a long list inside OR",
      { where: { OR: [{ id: { in: ids } }, { kvk: "1" }] } },
      "no top-level in list",
    ],
  ] as const)(
    "returns invalid_request for %s",
    async (_name, args, message) => {
      const { client, requests } = capturingClient();
      const result = await betterSupabase
        .connect(client)
        .customers.findMany(args as never);
      expect(result.error).toMatchObject({
        kind: "invalid_request",
        table: "customers",
        message: expect.stringContaining(message),
      });
      expect(requests).toHaveLength(0);
    },
  );

  it("returns invalid_request for a page of a long list", async () => {
    const { client, requests } = capturingClient();
    const page = await betterSupabase.connect(client).customers.paginate({
      where: { id: { in: ids } },
      include: { notes: { where: { OR: [{ kind: "call" }, { body: "x" }] } } },
      size: 20,
    });
    expect(page.error?.kind).toBe("invalid_request");
    expect(requests).toHaveLength(0);
  });

  it("refuses a read whose other filters leave no room for the list", async () => {
    const { client } = capturingClient();
    const result = await defineSupabase(schema, { urlLengthLimit: 200 })
      .connect(client)
      .customers.findMany({
        where: { id: { in: ids.slice(0, 20) }, name: { in: ids.slice(0, 5) } },
      });
    expect(result.error?.message).toContain("leaves no room");
  });

  it.each([
    ["updateMany", { where: { id: { in: ids } }, data: { status: "active" } }],
    ["deleteMany", { where: { id: { in: ids } } }],
  ] as const)(
    "returns invalid_request for a %s whose URL is too long",
    async (method, args) => {
      const { client, requests } = capturingClient();
      const { customers } = betterSupabase.connect(client);
      const result = await (method === "updateMany"
        ? customers.updateMany(args as never)
        : customers.deleteMany(args as never));
      expect(result.error).toMatchObject({
        kind: "invalid_request",
        table: "customers",
        message: expect.stringContaining("a write can't be split"),
      });
      expect(requests).toHaveLength(0);
    },
  );

  it("passes the first error through", async () => {
    let call = 0;
    const { client } = capturingClient(() => {
      call += 1;
      return call === 2
        ? { status: 500, body: { code: "XX000", message: "boom" } }
        : { body: [] };
    });
    const result = await betterSupabase
      .connect(client)
      .customers.findMany({ where: { id: { in: ids } } });
    expect(result.error?.message).toBe("boom");
  });
});

describe("oversized in lists on other key types", () => {
  const column = (db: string, type: string, extra: object = {}) => ({
    db,
    type,
    nullable: false,
    hasDefault: false,
    ...extra,
  });
  const meta: SchemaMeta = {
    version: 1,
    casing: "camel",
    enums: {},
    functions: {},
    tables: {
      countries: {
        key: "countries",
        name: "countries",
        schema: "public",
        kind: "table",
        columns: { code: column("code", "text"), name: column("name", "text") },
        primaryKey: ["code"],
        uniqueKeys: {},
        relations: {},
        flags: {},
      },
      ledger: {
        key: "ledger",
        name: "ledger",
        schema: "public",
        kind: "table",
        columns: {
          id: column("id", "int8", { codec: "bigint" }),
          seq: column("seq", "int8"),
          memo: column("memo", "text"),
        },
        primaryKey: ["id"],
        uniqueKeys: {},
        relations: {},
        flags: {},
      },
    },
  };
  const betterSupabase = defineSupabase(defineSchema(meta), {
    urlLengthLimit: 4000,
  });
  interface Repository {
    findMany(args: object): PromiseLike<{
      readonly data: Record<string, unknown>[] | null;
      readonly error: { readonly message: string } | null;
    }> & { orThrow(): Promise<Record<string, unknown>[]> };
  }
  const connect = (client: SupabaseClient) =>
    betterSupabase.connect(client) as never as {
      countries: Repository;
      ledger: Repository;
    };
  const codes = Array.from(
    { length: 400 },
    (_, index) => `code-${String(index).padStart(4, "0")}`,
  );

  it("splits a read on a text primary key without an orderBy", async () => {
    const { client, requests } = capturingClient((request) => ({
      body: listOf(request.params.get("code"))
        .map((code) => ({ code, name: code }))
        .reverse(),
    }));
    const rows = await connect(client)
      .countries.findMany({ where: { code: { in: codes } } })
      .orThrow();
    expect(requests.length).toBeGreaterThan(1);
    expect(rows.map((row) => row["code"])).toEqual(codes);
  });

  it("still refuses an orderBy on text the caller asked for", async () => {
    const { client, requests } = capturingClient();
    const result = await connect(client).countries.findMany({
      where: { code: { in: codes } },
      orderBy: { name: "asc" },
    });
    expect(result.error?.message).toContain("can't be re-applied");
    expect(requests).toHaveLength(0);
  });

  it("sorts int8 values past 2^53 exactly", async () => {
    const big = (index: number) => (2n ** 53n + BigInt(index)).toString();
    const keys = Array.from({ length: 400 }, (_, index) => big(index));
    const { client, requests } = capturingClient((request) => ({
      body: listOf(request.params.get("id"))
        .map((id) => ({ memo: id, _bs_order0: id }))
        .reverse(),
    }));
    const rows = await connect(client)
      .ledger.findMany({
        select: ["memo"],
        where: { id: { in: keys.map(BigInt) } },
        orderBy: { seq: "asc" },
      })
      .orThrow();
    expect(requests.length).toBeGreaterThan(1);
    expect(requests[0]?.params.get("select")).toBe("memo,_bs_order0:seq::text");
    expect(rows.map((row) => row["memo"])).toEqual(keys);
  });
});
