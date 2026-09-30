import { describe, expect, it } from "vitest";
import { z } from "zod";

import type { Executor } from "../core/executor.ts";

import { defineSupabase } from "../core/define.ts";
import { ok } from "../core/result.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { defineListQuery } from "../list/index.ts";
import { defineResource } from "./resource.ts";

const sb = defineSupabase(schema);

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
  return { db: sb.connect(executor), queries };
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
    const customers = defineResource(sb, "customers", {
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
    const customers = defineResource(sb, "customers", {
      operations: ["list", "get", "create"],
      input: {
        create: z.object({
          name: z.string().min(2),
          organizationId: z.string(),
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

  it("runs a list definition for GET collection requests", async () => {
    const { db, queries } = fakeDb();
    const list = defineListQuery(sb, "customers", {
      search: ["name"],
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
      pageSize: 10,
    });
    const customers = defineResource(sb, "customers", { list });
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
    expect(() => defineResource(sb, "tags" as never, { list })).toThrow(
      'not "tags"',
    );
  });
});
