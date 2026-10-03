import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { Executor } from "../../src/core/executor.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { ok } from "../../src/core/result.ts";
import { defineListQuery } from "../../src/list/index.ts";
import { defineResource } from "../../src/server/resource.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

function fakeDb() {
  const queries: Parameters<Executor["execute"]>[0][] = [];
  const executor: Executor = {
    name: "fake",
    execute: (query) => {
      queries.push(query);
      return Promise.resolve(
        ok({ rows: [{ id: "c1", name: "Acme" }], count: 1 }),
      );
    },
  };
  return { db: betterSupabase.connect(executor), queries };
}

const request = (path: string, init: RequestInit = {}) =>
  new Request(`https://api.test${path}`, init);

const json = (method: string, body: unknown): RequestInit => ({
  method,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

describe("defineResource", () => {
  it("serves CRUD with the status codes createOpenApi documents", async () => {
    const { db, queries } = fakeDb();
    const customers = defineResource(betterSupabase, "customers", {
      select: ["id", "name"],
    });
    expect(customers.keyParam).toBe("id");

    const list = await customers.handle(
      request("/customers?size=5"),
      db,
      undefined,
    );
    expect(list.status).toBe(200);
    expect(await list.json()).toMatchObject({
      items: [{ id: "c1" }],
      page: { number: 1, size: 5, total: 1 },
    });

    const created = await customers.handle(
      request(
        "/customers",
        json("POST", { name: "Acme", organizationId: "o1" }),
      ),
      db,
      undefined,
    );
    expect(created.status).toBe(201);

    expect(
      (await customers.handle(request("/customers/c1"), db, "c1")).status,
    ).toBe(200);
    expect(
      (
        await customers.handle(
          request("/customers/c1", json("PATCH", { name: "B" })),
          db,
          "c1",
        )
      ).status,
    ).toBe(200);
    expect(
      (
        await customers.handle(
          request("/customers/c1", { method: "DELETE" }),
          db,
          "c1",
        )
      ).status,
    ).toBe(204);
    expect(queries.map((query) => query.kind)).toEqual([
      "select",
      "insert",
      "select",
      "update",
      "delete",
    ]);
  });

  it("rejects bad bodies, paging and methods", async () => {
    const { db, queries } = fakeDb();
    const customers = defineResource(betterSupabase, "customers", {
      operations: ["list", "get", "create"],
      input: {
        create: v.object({
          name: v.pipe(v.string(), v.minLength(2)),
          organizationId: v.string(),
        }),
      },
    });
    const invalid = await customers.handle(
      request("/customers", json("POST", { name: "x", organizationId: "o1" })),
      db,
      undefined,
    );
    expect(invalid.status).toBe(422);
    expect(await invalid.json()).toMatchObject({
      kind: "validation",
      issues: [{ path: ["name"] }],
    });
    const notJson = await customers.handle(
      request("/customers", { method: "POST", body: "[1]" }),
      db,
      undefined,
    );
    expect(notJson.status).toBe(400);
    expect(await notJson.json()).toMatchObject({
      kind: "invalid_input",
      detail: "The request body must be a JSON object",
    });
    expect(
      (await customers.handle(request("/customers?size=999"), db, undefined))
        .status,
    ).toBe(422);
    const deleting = await customers.handle(
      request("/customers/c1", { method: "DELETE" }),
      db,
      "c1",
    );
    expect(deleting.status).toBe(405);
    expect(deleting.headers.get("allow")).toBe("GET");
    expect(queries).toEqual([]);
  });

  it("refuses cross-site form posts that ride on the session cookie", async () => {
    const { db, queries } = fakeDb();
    const customers = defineResource(betterSupabase, "customers");
    const post = (headers: Record<string, string>) =>
      customers.handle(
        request("/customers", {
          method: "POST",
          headers,
          body: JSON.stringify({ name: "Acme", organizationId: "o1" }),
        }),
        db,
        undefined,
      );
    const forged = await post({
      origin: "https://evil.test",
      "content-type": "text/plain",
      cookie: "sb-session=x",
    });
    expect(forged.status).toBe(403);
    expect(await forged.json()).toMatchObject({ code: "CROSS_SITE_REQUEST" });
    expect(queries).toHaveLength(0);

    for (const headers of [
      { origin: "https://evil.test", "content-type": "application/json" },
      { origin: "https://evil.test", authorization: "Bearer t" },
      { origin: "https://api.test", "content-type": "text/plain" },
      { "content-type": "text/plain" },
    ]) {
      expect((await post(headers)).status).toBe(201);
    }
  });

  it("runs a list definition for GET collection requests", async () => {
    const { db, queries } = fakeDb();
    const list = defineListQuery(betterSupabase, "customers", {
      search: ["name"],
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
      pageSize: 10,
    });
    const customers = defineResource(betterSupabase, "customers", { list });
    const response = await customers.handle(
      request("/customers?q=acme&sort=name"),
      db,
      undefined,
    );
    expect(response.status).toBe(200);
    expect(queries[0]).toMatchObject({ kind: "select", limit: 11 });
    expect(
      (await customers.handle(request("/customers?sort=nope"), db, undefined))
        .status,
    ).toBe(422);
    expect(() =>
      defineResource(betterSupabase, "tags" as never, { list }),
    ).toThrow('not "tags"');
  });

  it("pages the default list by cursor", async () => {
    const { db, queries } = fakeDb();
    const customers = defineResource(betterSupabase, "customers", {
      pagination: "cursor",
      maxPageSize: 5,
    });
    expect(customers.pagination).toBe("cursor");
    const first = await customers.execute(db, "list", {
      query: new URLSearchParams("size=1"),
    });
    expect(first.ok && first.data).toMatchObject({
      items: [{ id: "c1" }],
      hasMore: false,
      nextCursor: null,
    });
    expect(queries[0]).toMatchObject({ kind: "select", limit: 2 });
    expect((queries[0] as { count?: unknown }).count).toBeUndefined();
    const rejected = await customers.execute(db, "list", {
      query: { page: 2, after: 3, size: 9 },
    });
    expect(!rejected.ok && rejected.error).toMatchObject({
      kind: "validation",
      issues: [
        { path: ["size"] },
        { message: "This list pages with `after`", path: ["page"] },
        { message: "Must be text", path: ["after"] },
      ],
    });
    const offset = defineResource(betterSupabase, "customers");
    expect(offset.pagination).toBe("offset");
    const mixed = await offset.execute(db, "list", {
      query: { after: "x", page: 0 },
    });
    expect(!mixed.ok && mixed.error).toMatchObject({
      issues: [
        { message: "This list pages with `page`", path: ["after"] },
        { message: "Must be a positive integer", path: ["page"] },
      ],
    });
    const list = defineListQuery(betterSupabase, "customers", {
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
      pagination: "cursor",
    });
    expect(
      defineResource(betterSupabase, "customers", { list }).pagination,
    ).toBe("cursor");
  });
});
