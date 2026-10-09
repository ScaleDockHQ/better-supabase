import { QueryClient, skipToken } from "@tanstack/query-core";
import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { DbException } from "../../src/core/errors.ts";
import { createQueries } from "../../src/query/index.ts";
import { collectionOptions } from "../../src/tanstack-db/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

/** Partial fixture rows stand in for the full rows TanStack DB passes. */
function mutations(
  ...items: { original?: unknown; modified: object; changes?: object }[]
): never {
  const params = {
    transaction: {
      mutations: items.map((item) => ({
        original: item.original ?? {},
        modified: item.modified,
        changes: item.changes ?? {},
      })),
    },
  };
  return params as never;
}

describe("collectionOptions", () => {
  it("loads through the query and keys rows by the primary key", async () => {
    const { client } = capturingClient(() => ({
      body: [{ id: "c1", name: "Acme" }],
    }));
    const db = betterSupabase.connect(client);
    const queries = createQueries(betterSupabase, db);
    const queryClient = new QueryClient();
    const query = queries.customers.findMany({ select: ["id", "name"] });
    const config = collectionOptions(betterSupabase, db, "customers", {
      query,
      queryClient,
    });
    expect(config.id).toBe("customers");
    expect(config.queryKey).toBe(query.queryKey);
    expect(config.meta?.bsTables).toEqual(["customers"]);
    const rows = await config.queryFn({ signal: new AbortController().signal });
    expect(rows).toEqual([{ id: "c1", name: "Acme" }]);
    expect(config.getKey({ id: "c1", name: "Acme" })).toBe("c1");
  });

  it("sends inserts, updates and deletes through the repository", async () => {
    const { client, requests } = capturingClient(() => ({
      body: [{ id: "c2" }],
      headers: { "content-range": "0-0/1" },
    }));
    const db = betterSupabase.connect(client);
    const queryClient = new QueryClient();
    const queries = createQueries(betterSupabase, db);
    const query = queries.customers.findMany({});
    const config = collectionOptions(betterSupabase, () => db, "customers", {
      query,
      queryClient,
      id: "active-customers",
    });
    expect(config.id).toBe("active-customers");

    await expect(
      config.onInsert(
        mutations({ modified: { id: "c2", name: "Beta", status: "active" } }),
      ),
    ).resolves.toBeUndefined();
    expect(requests.at(-1)).toMatchObject({
      method: "POST",
      path: "/rest/v1/customers",
      body: { id: "c2", name: "Beta", status: "active" },
    });

    await config.onUpdate(
      mutations({
        original: { id: "c2", name: "Beta" },
        modified: { id: "c2", name: "Gamma" },
        changes: { name: "Gamma" },
      }),
    );
    expect(requests.at(-1)?.method).toBe("PATCH");
    expect(requests.at(-1)?.params.get("id")).toBe("eq.c2");
    expect(requests.at(-1)?.body).toEqual({ name: "Gamma" });

    await config.onDelete(
      mutations({ original: { id: "c2" }, modified: { id: "c2" } }),
    );
    expect(requests.at(-1)?.method).toBe("DELETE");
    expect(requests.at(-1)?.params.get("id")).toBe("eq.c2");
  });

  it("keys composite primary keys and filters writes by every column", async () => {
    const { client, requests } = capturingClient(() => ({
      body: [{ customerId: "c1", tagId: "t1" }],
      headers: { "content-range": "0-0/1" },
    }));
    const db = betterSupabase.connect(client);
    const queries = createQueries(betterSupabase, db);
    const config = collectionOptions(betterSupabase, db, "customerTags", {
      query: queries.customerTags.findMany({}),
      queryClient: new QueryClient(),
    });
    const row = { customerId: "c1", tagId: "t1" };
    expect(config.getKey(row as never)).toBe('["c1","t1"]');
    await config.onDelete(mutations({ original: row, modified: row }));
    expect(requests.at(-1)?.params.get("customer_id")).toBe("eq.c1");
    expect(requests.at(-1)?.params.get("tag_id")).toBe("eq.t1");
  });

  it("rejects a failed write with a DbException", async () => {
    const { client } = capturingClient(() => ({
      status: 409,
      body: { code: "23505", message: "duplicate key", details: null },
    }));
    const db = betterSupabase.connect(client);
    const queries = createQueries(betterSupabase, db);
    const config = collectionOptions(betterSupabase, db, "customers", {
      query: queries.customers.findMany({}),
      queryClient: new QueryClient(),
    });
    await expect(
      config.onInsert(mutations({ modified: { id: "c1", name: "Acme" } })),
    ).rejects.toBeInstanceOf(DbException);
  });

  it("needs a query that runs", () => {
    const db = betterSupabase.connect(capturingClient().client);
    expect(() =>
      collectionOptions(betterSupabase, db, "customers", {
        query: { queryKey: ["bs"], queryFn: skipToken },
        queryClient: new QueryClient(),
      }),
    ).toThrow(/skipToken/);
  });
});
