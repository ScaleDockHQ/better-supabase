import { hashKey, QueryClient, skipToken } from "@tanstack/query-core";
import { describe, expect, it } from "vitest";

import type { Executor } from "../../src/core/executor.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { DbException } from "../../src/core/errors.ts";
import { ok } from "../../src/core/result.ts";
import {
  createQueries,
  invalidateOnMutation,
  invalidateTables,
} from "../../src/query/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

function isInvalid(
  client: QueryClient,
  key: readonly unknown[],
): boolean | undefined {
  return client.getQueryCache().find({ queryKey: key, exact: true })?.state
    .isInvalidated;
}

describe("createQueries", () => {
  it("builds stable keys, table meta and runs through the repository", async () => {
    const { client, last } = capturingClient(() => ({
      body: [{ id: "c1", name: "Acme" }],
    }));
    const q = createQueries(betterSupabase, betterSupabase.connect(client));
    const options = q.customers.findMany({
      select: ["id", "name"],
      where: { status: "active" },
      include: { notes: { select: ["id"] } },
    });
    expect(options.queryKey).toEqual([
      "bs",
      "customers",
      "findMany",
      {
        select: ["id", "name"],
        where: { status: "active" },
        include: { notes: { select: ["id"] } },
      },
    ]);
    expect(options.meta.bsTables).toEqual(["customers", "notes"]);
    expect(q.customers.key).toEqual(["bs", "customers"]);
    expect(q.$key).toEqual(["bs"]);

    const queryClient = new QueryClient();
    expect(await queryClient.query(options)).toEqual([
      { id: "c1", name: "Acme" },
    ]);
    expect(last().params.get("status")).toBe("eq.active");
  });

  it("rejects with DbException", async () => {
    const { client } = capturingClient(() => ({
      status: 403,
      body: { code: "42501", message: "denied" },
    }));
    const q = createQueries(betterSupabase, betterSupabase.connect(client));
    await expect(
      new QueryClient().query(q.customers.count()),
    ).rejects.toBeInstanceOf(DbException);
  });

  it("passes skipToken through as the queryFn", () => {
    const q = createQueries(
      betterSupabase,
      betterSupabase.connect(capturingClient().client),
    );
    expect(q.customers.findById(skipToken).queryFn).toBe(skipToken);
    expect(q.customers.findMany(skipToken).queryKey).toEqual([
      "bs",
      "customers",
      "findMany",
      "$skip",
    ]);
  });

  it("hashes keys whose arguments hold bigint values", async () => {
    const { client, last } = capturingClient(() => ({ body: [] }));
    const q = createQueries(betterSupabase, betterSupabase.connect(client));
    const where = { id: { in: [9007199254740993n] } };
    const options = [
      q.notes.findMany({ where } as never),
      q.notes.infinite({ where, size: 5 } as never),
      q.notes.infinitePages({ where, size: 5 } as never),
      q.$rpc("lookup" as never, { id: 9007199254740993n } as never),
    ];
    for (const option of options)
      expect(() => hashKey(option.queryKey)).not.toThrow();
    expect(options[0]?.queryKey).toEqual([
      "bs",
      "notes",
      "findMany",
      { where: { id: { in: [{ $bigint: "9007199254740993" }] } } },
    ]);
    expect(hashKey(options[0]!.queryKey)).not.toBe(
      hashKey(
        q.notes.findMany({ where: { id: { in: [9007199254740992] } } })
          .queryKey,
      ),
    );
    await new QueryClient().query(options[0] as never);
    expect(last().params.get("id")).toBe("in.(9007199254740993)");
  });

  it("applies the configured staleTime", () => {
    const q = createQueries(
      betterSupabase,
      betterSupabase.connect(capturingClient().client),
      {
        staleTime: 30_000,
      },
    );
    expect(q.customers.count().staleTime).toBe(30_000);
    expect(q.customers.infinite({ size: 5 }).staleTime).toBe(30_000);
  });

  it("pages cursors for useInfiniteQuery", async () => {
    const { client, requests } = capturingClient(() => ({
      body: [
        { id: "a", name: "A" },
        { id: "b", name: "B" },
      ],
    }));
    const q = createQueries(betterSupabase, betterSupabase.connect(client));
    const options = q.customers.infinite({
      select: ["id", "name"],
      size: 1,
      orderBy: { name: "asc" },
    });
    const data = await new QueryClient().infiniteQuery(options);
    expect(data.pages[0]).toMatchObject({
      items: [{ id: "a", name: "A" }],
      hasMore: true,
    });
    expect(options.getNextPageParam(data.pages[0]!)).toEqual(
      expect.any(String),
    );
    expect(requests[0]!.params.get("limit")).toBe("2");
  });

  it("pages numbers for useInfiniteQuery", async () => {
    const { client, requests } = capturingClient(() => ({
      body: [{ id: "a" }, { id: "b" }, { id: "c" }],
    }));
    const q = createQueries(betterSupabase, betterSupabase.connect(client));
    const options = q.customers.infinitePages({
      select: ["id"],
      size: 2,
      page: 2,
    });
    expect(options.initialPageParam).toBe(2);
    const data = await new QueryClient().infiniteQuery(options);
    expect(requests[0]!.params.get("offset")).toBe("2");
    expect(options.getNextPageParam(data.pages[0]!)).toBe(3);
  });

  it("turns specs into query options and prefetches them", async () => {
    const { client } = capturingClient(() => ({ body: [{ id: "c1" }] }));
    const q = createQueries(betterSupabase, betterSupabase.connect(client));
    const spec = betterSupabase.spec.customers.findMany({ select: ["id"] });
    const shipped = JSON.parse(JSON.stringify(spec)) as typeof spec;
    expect(q.$spec(shipped).queryKey).toEqual(
      q.customers.findMany({ select: ["id"] }).queryKey,
    );
    const queryClient = new QueryClient();
    await q.$prefetch(queryClient, shipped);
    expect(queryClient.getQueryData(q.$spec(shipped).queryKey)).toEqual([
      { id: "c1" },
    ]);
  });

  it("invalidates every query that read a changed table", async () => {
    const { client } = capturingClient(() => ({
      body: [{ id: "c1", name: "New" }],
    }));
    const db = betterSupabase.connect(client);
    const q = createQueries(betterSupabase, () => db);
    const queryClient = new QueryClient();
    const withNotes = q.notes.findMany({ include: { customer: true } });
    const organizations = q.organizations.findMany();
    queryClient
      .getQueryCache()
      .build(queryClient, {
        queryKey: withNotes.queryKey,
        meta: withNotes.meta,
      })
      .setData([]);
    queryClient.setQueryData(organizations.queryKey, []);
    queryClient.setQueryData(["bs", "customers", "custom"], 1);

    const options = q.customers.update({ select: ["id", "name"] });
    const data = await options.mutationFn({ id: "c1", patch: { name: "New" } });
    await options.onSuccess(
      data,
      { id: "c1", patch: { name: "New" } },
      undefined,
      {
        client: queryClient,
      },
    );
    expect(isInvalid(queryClient, withNotes.queryKey)).toBe(true);
    expect(isInvalid(queryClient, ["bs", "customers", "custom"])).toBe(true);
    expect(isInvalid(queryClient, organizations.queryKey)).toBe(false);

    const stop = invalidateOnMutation(betterSupabase, queryClient);
    queryClient.setQueryData(["bs", "customerTags", "x"], 1);
    await db.tags.delete("t1").orThrow();
    await new Promise((resolve) => {
      setTimeout(resolve, 0);
    });
    expect(isInvalid(queryClient, ["bs", "customerTags", "x"])).toBe(true);
    stop();
  });

  it("ignores an empty table list", async () => {
    const queryClient = new QueryClient();
    queryClient.setQueryData(["bs", "customers"], 1);
    await invalidateTables(queryClient, []);
    expect(isInvalid(queryClient, ["bs", "customers"])).toBe(false);
  });

  it("builds rpc query and mutation options", async () => {
    const calls: string[] = [];
    const executor: Executor = {
      name: "rpc",
      execute: () => Promise.resolve(ok({ rows: [], count: null })),
      rpc: (name) => {
        calls.push(name);
        return Promise.resolve(ok(42));
      },
    };
    const withRpc = betterSupabase.defineRpc("archive_customer" as never, {
      invalidates: ["customers"],
    });
    const q = createQueries(withRpc, withRpc.connect(executor));
    const rpc = q.$rpc("customer_stats" as never, undefined, {
      tables: ["customers"],
    });
    expect(rpc.queryKey).toEqual(["bs", "$rpc", "customer_stats", {}]);
    expect(rpc.meta.bsTables).toEqual(["customers"]);
    const queryClient = new QueryClient();
    expect(await queryClient.query(rpc)).toBe(42);

    const mutation = q.$rpcMutation("archive_customer" as never);
    await mutation.mutationFn({} as never);
    await mutation.onSuccess(42 as never, {} as never, undefined, {
      client: queryClient,
    });
    expect(isInvalid(queryClient, rpc.queryKey)).toBe(true);
    expect(calls).toEqual(["customer_stats", "archive_customer"]);
  });
});
