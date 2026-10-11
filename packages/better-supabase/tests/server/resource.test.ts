import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { Executor } from "../../src/core/executor.ts";

import {
  defineAuthorizer,
  type AuthorizationOutcome,
  type AuthorizationRequest,
} from "../../src/core/authorizer.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { defineListQuery } from "../../src/list/index.ts";
import { defineAction } from "../../src/server/resource-execute.ts";
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

const grantAll = defineAuthorizer({
  name: "test",
  key: (ref: string) => ref,
  evaluate: () => ({ outcome: "granted" as const }),
});

function authorizerOf(
  decide: (request: AuthorizationRequest) => AuthorizationOutcome,
) {
  const requests: AuthorizationRequest[] = [];
  const authorizer = defineAuthorizer({
    name: "test",
    key: (ref: string) => ref,
    evaluate: (request) => {
      requests.push(request);
      return decide(request);
    },
  });
  return { authorizer, requests };
}

function userDb() {
  const queries: Parameters<Executor["execute"]>[0][] = [];
  const executor: Executor = {
    name: "fake",
    execute: (query) => {
      queries.push(query);
      return Promise.resolve(
        ok({
          rows: [
            { id: "c1", name: "Acme", organizationId: "o1" },
            { id: "c2", name: "Beta", organizationId: "o2" },
          ],
          count: 2,
        }),
      );
    },
  };
  const db = betterSupabase.connect(executor, {
    actor: { kind: "user", id: "u1", role: "authenticated" },
    tenant: "o1",
    claims: { scope: "read write" },
  });
  return { db, queries };
}

describe("defineResource actions", () => {
  it("routes collection, item and action paths through serve()", async () => {
    const { db } = fakeDb();
    const seen: unknown[] = [];
    const customers = defineResource(betterSupabase, "customers", {
      actions: {
        send: defineAction({
          method: "POST",
          path: "/{id}/send",
          input: v.object({ subject: v.string() }),
          status: 202,
          handler: (ctx, { id, data }) => {
            seen.push([ctx.table, id, data.subject, ctx.request?.method]);
            return ok({ queued: true });
          },
        }),
        export: {
          method: "GET",
          path: "/export",
          query: v.object({ format: v.picklist(["csv", "json"]) }),
          handler: (_ctx, { query }) => ({ query }),
        },
        ping: {
          method: "POST",
          path: "/ping",
          handler: () => undefined,
        },
      },
    });
    expect(customers.plan.actions.map((action) => action.name)).toEqual([
      "send",
      "export",
      "ping",
    ]);

    const sent = await customers.serve(
      request("/customers/c1/send", json("POST", { subject: "Hi" })),
      db,
      "c1/send",
    );
    expect(sent.status).toBe(202);
    expect(await sent.json()).toEqual({ queued: true });
    expect(seen).toEqual([["customers", "c1", "Hi", "POST"]]);

    const exported = await customers.serve(
      request("/customers/export?format=csv"),
      db,
      ["export"],
    );
    expect(await exported.json()).toEqual({ query: { format: "csv" } });
    expect(
      (
        await customers.serve(
          request("/customers/export?format=x"),
          db,
          "export",
        )
      ).status,
    ).toBe(422);
    expect(
      (
        await customers.serve(
          request("/customers/ping", { method: "POST" }),
          db,
          "/ping/",
        )
      ).status,
    ).toBe(204);

    const wrong = await customers.serve(
      request("/customers/c1/send"),
      db,
      "c1/send",
    );
    expect(wrong.status).toBe(405);
    expect(wrong.headers.get("allow")).toBe("POST");
    const invalid = await customers.serve(
      request("/customers/c1/send", json("POST", { subject: 1 })),
      db,
      "c1/send",
    );
    expect(invalid.status).toBe(422);
    expect(
      (await customers.serve(request("/customers/a/b/c"), db, "a/b/c")).status,
    ).toBe(404);
    expect((await customers.serve(request("/customers"), db, "")).status).toBe(
      200,
    );
    expect(
      (await customers.serve(request("/customers/c1"), db, "c1")).status,
    ).toBe(200);
    expect(
      (await customers.serve(request("/customers/%E0"), db, "%E0")).status,
    ).toBe(400);
    // handle() keeps its old routing: "export" is an id there.
    expect(
      (await customers.handle(request("/customers/export"), db, "export"))
        .status,
    ).toBe(200);
  });

  it("turns a throwing handler into an unexpected error", async () => {
    const { db } = fakeDb();
    const customers = defineResource(betterSupabase, "customers", {
      actions: {
        boom: {
          method: "POST",
          path: "/boom",
          handler: () => {
            throw new Error("secret detail");
          },
        },
        refuse: {
          method: "POST",
          path: "/refuse",
          handler: () => err(dbError("conflict", "Already sent")),
        },
      },
    });
    const boom = await customers.action(db, "boom");
    expect(!boom.ok && boom.error).toMatchObject({
      kind: "unexpected",
      message: "The boom action failed",
    });
    const refused = await customers.action(db, "refuse");
    expect(!refused.ok && refused.error.kind).toBe("conflict");
    const missing = await customers.action(db, "nope");
    expect(!missing.ok && missing.error.kind).toBe("not_found");
  });
});

describe("defineResource hooks", () => {
  it("runs before and after hooks around the repository", async () => {
    const { db, queries } = fakeDb();
    const calls: string[] = [];
    const customers = defineResource(betterSupabase, "customers", {
      hooks: {
        authorize: (_ctx, operation) => {
          calls.push(`authorize:${operation}`);
          return ok(undefined);
        },
        beforeCreate: (_ctx, data) => ok({ ...data, name: data.name.trim() }),
        beforeUpdate: (_ctx, data) => ok({ ...data, name: "Changed" }),
        beforeDelete: () => {
          calls.push("beforeDelete");
          return ok(undefined);
        },
        afterGet: (_ctx, row) => ok({ id: row.id, extra: true }),
        afterList: (_ctx, page) => ok({ count: page.items.length }),
        afterCreate: (_ctx, row) => ok({ created: row.id }),
        afterUpdate: (_ctx, row) => ok({ updated: row.id }),
      },
    });
    const created = await customers.execute(db, "create", {
      data: { name: "  Acme ", organizationId: "o1" },
    });
    expect(created).toMatchObject({ ok: true, data: { created: "c1" } });
    expect(queries[0]).toMatchObject({ kind: "insert" });
    expect(JSON.stringify(queries[0])).toContain('"Acme"');
    expect(await customers.execute(db, "get", { id: "c1" })).toMatchObject({
      data: { id: "c1", extra: true },
    });
    expect(await customers.execute(db, "list", {})).toMatchObject({
      data: { count: 1 },
    });
    expect(
      await customers.execute(db, "update", { id: "c1", data: { name: "x" } }),
    ).toMatchObject({ data: { updated: "c1" } });
    expect(JSON.stringify(queries.at(-1))).toContain('"Changed"');
    expect((await customers.execute(db, "delete", { id: "c1" })).ok).toBe(true);
    expect(calls).toEqual([
      "authorize:create",
      "authorize:get",
      "authorize:list",
      "authorize:update",
      "authorize:delete",
      "beforeDelete",
    ]);
  });

  it("stops on an error Result and maps throws and plain values to unexpected", async () => {
    const { db, queries } = fakeDb();
    const denied = defineResource(betterSupabase, "customers", {
      hooks: {
        authorize: () => err(dbError("forbidden", "Not yours")),
      },
    });
    const response = await denied.handle(request("/customers"), db, undefined);
    expect(response.status).toBe(403);
    expect(queries).toHaveLength(0);

    const throwing = defineResource(betterSupabase, "customers", {
      hooks: {
        beforeCreate: () => {
          throw new Error("secret");
        },
      },
    });
    const thrown = await throwing.execute(db, "create", {
      data: { name: "A", organizationId: "o1" },
    });
    expect(!thrown.ok && thrown.error).toMatchObject({
      kind: "unexpected",
      message: "The beforeCreate hook failed",
    });
    const plain = defineResource(betterSupabase, "customers", {
      // @ts-expect-error hooks return a Result
      hooks: { afterGet: () => ({ id: "c1" }) },
    });
    const value = await plain.execute(db, "get", { id: "c1" });
    expect(!value.ok && value.error.message).toBe(
      "The afterGet hook must return a Result",
    );
    expect(queries.map((query) => query.kind)).toEqual(["select"]);
  });
});

describe("defineResource permissions", () => {
  it("checks the permission with the fetched row before update", async () => {
    const { db, queries } = userDb();
    const { authorizer, requests } = authorizerOf((request) =>
      request.resource.properties?.["organizationId"] === "o1"
        ? { outcome: "granted" }
        : { outcome: "denied", reason: "Wrong organization" },
    );
    const customers = defineResource(
      betterSupabase,
      "customers",
      { permissions: { update: "customers.update", get: "customers.read" } },
      authorizer,
    );
    expect(customers.plan.permissions).toEqual({
      update: "customers.update",
      get: "customers.read",
    });
    const updated = await customers.execute(db, "update", {
      id: "c1",
      data: { name: "B" },
    });
    expect(updated.ok).toBe(true);
    expect(queries.map((query) => query.kind)).toEqual(["select", "update"]);
    expect(requests[0]).toEqual({
      subject: {
        type: "user",
        id: "u1",
        properties: {
          role: "authenticated",
          claims: { scope: "read write" },
        },
      },
      action: "customers.update",
      resource: {
        type: "customers",
        id: "c1",
        properties: { id: "c1", name: "Acme", organizationId: "o1" },
      },
      context: { tenant: "o1", scopes: ["read", "write"] },
    });
    expect(
      (
        await customers.execute(db, "create", {
          data: { name: "N", organizationId: "o1" },
        })
      ).ok,
    ).toBe(true);
    expect(requests).toHaveLength(1);
  });

  it("denies before the repository writes and fails closed", async () => {
    const { db, queries } = userDb();
    const { authorizer } = authorizerOf(() => ({
      outcome: "denied",
      reason: "No",
    }));
    const customers = defineResource(
      betterSupabase,
      "customers",
      {
        permissions: { delete: "customers.delete", create: "customers.create" },
      },
      authorizer,
    );
    const deleted = await customers.handle(
      request("/customers/c1", { method: "DELETE" }),
      db,
      "c1",
    );
    expect(deleted.status).toBe(403);
    expect(await deleted.json()).toMatchObject({
      code: "PERMISSION_DENIED",
      permission: "customers.delete",
    });
    const created = await customers.execute(db, "create", {
      data: { name: "N", organizationId: "o1" },
    });
    expect(!created.ok && created.error.code).toBe("PERMISSION_DENIED");
    expect(queries.map((query) => query.kind)).toEqual(["select"]);

    const throwing = defineResource(
      betterSupabase,
      "customers",
      { permissions: { create: "customers.create" } },
      defineAuthorizer({
        name: "broken",
        key: (ref: string) => ref,
        evaluate: () => {
          throw new Error("down");
        },
      }),
    );
    const failed = await throwing.execute(db, "create", {
      data: { name: "N", organizationId: "o1" },
    });
    expect(!failed.ok && failed.error.kind).toBe("forbidden");

    const unset = defineResource(betterSupabase, "customers", {
      permissions: { create: "customers.create" },
    });
    const missing = await unset.execute(db, "create", {
      data: { name: "N", organizationId: "o1" },
    });
    expect(!missing.ok && missing.error.code).toBe("PERMISSION_DENIED");
  });

  it("answers 403 APPROVAL_REQUIRED with the approval id", async () => {
    const { db, queries } = userDb();
    const { authorizer } = authorizerOf(() => ({
      outcome: "approval-required",
      approval: { id: "apr_1" },
    }));
    const customers = defineResource(
      betterSupabase,
      "customers",
      {
        actions: {
          refund: {
            method: "POST",
            path: "/{id}/refund",
            permission: "customers.refund",
            handler: () => ok({ refunded: true }),
          },
        },
      },
      authorizer,
    );
    const response = await customers.serve(
      request("/customers/c1/refund", { method: "POST" }),
      db,
      "c1/refund",
    );
    expect(response.status).toBe(403);
    expect(await response.json()).toMatchObject({
      code: "APPROVAL_REQUIRED",
      permission: "customers.refund",
      approval: { id: "apr_1" },
    });
    expect(queries.map((query) => query.kind)).toEqual(["select"]);
  });

  it("filters list rows with one batch and keeps the request order", async () => {
    const { db } = userDb();
    const batches: AuthorizationRequest[][] = [];
    const authorizer = defineAuthorizer({
      name: "batch",
      key: (ref: string) => ref,
      evaluate: () => ({ outcome: "denied" as const }),
      evaluations: (requests) => {
        batches.push([...requests]);
        return Promise.resolve(
          requests.map((request) =>
            request.resource.id === "c2"
              ? { outcome: "granted" as const }
              : { outcome: "denied" as const },
          ),
        );
      },
    });
    const customers = defineResource(
      betterSupabase,
      "customers",
      { permissions: { list: "customers.read" } },
      authorizer,
    );
    const listed = await customers.execute(db, "list", {});
    expect(listed.ok && listed.data).toMatchObject({ items: [{ id: "c2" }] });
    expect(batches).toHaveLength(1);
    expect(batches[0]!.map((request) => request.resource.id)).toEqual([
      "c1",
      "c2",
    ]);

    const unset = defineResource(betterSupabase, "customers", {
      permissions: { list: "customers.read" },
    });
    const refused = await unset.execute(db, "list", {});
    expect(!refused.ok && refused.error.kind).toBe("forbidden");
  });

  it("asks forOperation for permissions: true and types refs from the authorizer", () => {
    const typed = defineAuthorizer<"read" | "write">({
      name: "typed",
      key: (ref) => ref,
      forOperation: (_table, operation) =>
        operation === "list" || operation === "get" ? "read" : "write",
      evaluate: () => ({ outcome: "granted" }),
    });
    const all = defineResource(
      betterSupabase,
      "customers",
      { permissions: true },
      typed,
    );
    expect(all.plan.permissions).toMatchObject({
      list: "read",
      delete: "write",
    });
    defineResource(
      betterSupabase,
      "customers",
      // @ts-expect-error "admin" is not a permission of this authorizer
      { permissions: { list: "admin" } },
      typed,
    );
    expect(() =>
      defineResource(
        betterSupabase,
        "customers",
        { permissions: true },
        grantAll,
      ),
    ).toThrow("forOperation");
  });
});
