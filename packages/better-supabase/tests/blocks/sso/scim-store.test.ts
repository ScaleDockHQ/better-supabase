import { describe, expect, it } from "vitest";

import type {
  ScimListQuery,
  ScimSaveInput,
  ScimStore,
  ScimStoredResource,
  ScimSyncEntry,
} from "../../../src/blocks/sso/index.ts";

import {
  matchesScimFilter,
  scimHandler,
  sqlScimStore,
  sqlScimSyncLog,
} from "../../../src/blocks/sso/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../../src/core/result.ts";

const ENTERPRISE = "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User";
const at = Temporal.Instant.from("2026-10-06T12:00:00Z");

/** A store over a map that applies the filter and paging itself. */
function pushDownStore() {
  const rows = new Map<string, ScimStoredResource>();
  const saves: ScimSaveInput[] = [];
  const queries: ScimListQuery[] = [];
  let next = 0;
  const store: ScimStore = {
    apiVersion: 1,
    list: async (_type, _tenant, query) => {
      queries.push(query);
      const all = [...rows.values()].filter((row) =>
        query.filter
          ? matchesScimFilter({ ...row.resource, id: row.id }, query.filter)
          : true,
      );
      return ok({
        resources: all.slice(
          query.startIndex - 1,
          query.startIndex - 1 + query.count,
        ),
        totalResults: all.length,
      });
    },
    get: async (_type, _tenant, id) => ok(rows.get(id)),
    save: async (_type, _tenant, input) => {
      saves.push(input);
      const existing = input.id === undefined ? undefined : rows.get(input.id);
      if (input.id !== undefined && existing === undefined) {
        return err(dbError("not_found", "No such user"));
      }
      if (existing && input.version !== existing.version) {
        return err(dbError("stale", "Changed"));
      }
      const id = input.id ?? `user-${++next}`;
      const row: ScimStoredResource = {
        id,
        resource: input.resource,
        version: (existing?.version ?? 0) + 1,
        created: existing?.created ?? at,
        lastModified: at,
      };
      rows.set(id, row);
      return ok(row);
    },
    delete: async (_type, _tenant, id) => ok(rows.delete(id)),
  };
  return { store, rows, saves, queries };
}

const keys = {
  verify: () =>
    AsyncResult.from(async () =>
      ok({
        status: "ok" as const,
        key: {
          id: "k1",
          organizationId: "org-a",
          userId: undefined,
          name: "Okta",
          prefix: "bs",
          publicId: "pub",
          scopes: ["scim"],
        } as never,
      }),
    ),
};

function request(method: string, path: string, body?: unknown, headers = {}) {
  return new Request(`https://app.test/scim/v2${path}`, {
    method,
    headers: {
      authorization: "Bearer token",
      "content-type": "application/scim+json",
      ...headers,
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
}

describe("scimHandler with a store", () => {
  it("hands the raw resource, extensions included, to the store", async () => {
    const { store, saves } = pushDownStore();
    const handler = scimHandler({ store, keys, basePath: "/scim/v2" });
    const response = await handler(
      request("POST", "/Users", {
        schemas: ["urn:ietf:params:scim:schemas:core:2.0:User", ENTERPRISE],
        userName: "ada@acme.test",
        [ENTERPRISE]: { department: "Engineering" },
      }),
    );
    expect(response.status).toBe(201);
    expect(saves[0]?.resource[ENTERPRISE]).toEqual({
      department: "Engineering",
    });
    expect(saves[0]?.data).toMatchObject({
      userName: "ada@acme.test",
      active: true,
    });
    const body = (await response.json()) as Record<string, unknown>;
    expect(body[ENTERPRISE]).toEqual({ department: "Engineering" });
    expect(body["meta"]).toMatchObject({
      resourceType: "User",
      location: "https://app.test/scim/v2/Users/user-1",
      version: 'W/"1"',
    });
    expect(response.headers.get("location")).toBe(
      "https://app.test/scim/v2/Users/user-1",
    );
  });

  it("trusts a store's own filter and paging", async () => {
    const { store, queries } = pushDownStore();
    const handler = scimHandler({ store, keys, basePath: "/scim/v2" });
    for (const name of ["a@acme.test", "b@acme.test", "c@acme.test"]) {
      await handler(
        request("POST", "/Users", {
          schemas: ["urn:ietf:params:scim:schemas:core:2.0:User"],
          userName: name,
        }),
      );
    }
    const response = await handler(
      request("GET", '/Users?filter=userName sw "a"&startIndex=1&count=1'),
    );
    const body = (await response.json()) as Record<string, unknown>;
    expect(queries.at(-1)?.filter).toBeDefined();
    expect(queries.at(-1)).toMatchObject({ startIndex: 1, count: 1 });
    expect(body).toMatchObject({ totalResults: 1, itemsPerPage: 1 });
  });

  it("maps a store's stale and not_found errors", async () => {
    const { store } = pushDownStore();
    const handler = scimHandler({ store, keys, basePath: "/scim/v2" });
    await handler(
      request("POST", "/Users", {
        schemas: ["urn:ietf:params:scim:schemas:core:2.0:User"],
        userName: "ada@acme.test",
      }),
    );
    const stale = await handler(
      request(
        "PUT",
        "/Users/user-1",
        {
          schemas: ["urn:ietf:params:scim:schemas:core:2.0:User"],
          userName: "ada@acme.test",
        },
        { "if-match": 'W/"7"' },
      ),
    );
    expect(stale.status).toBe(412);
    expect((await handler(request("GET", "/Users/nobody"))).status).toBe(404);
  });

  it("logs each write with its status and request id, never failing on the log", async () => {
    const { store } = pushDownStore();
    const entries: ScimSyncEntry[] = [];
    const handler = scimHandler({
      store,
      keys,
      basePath: "/scim/v2",
      log: {
        apiVersion: 1,
        record: async (entry) => {
          entries.push(entry);
          throw new Error("log down");
        },
      },
    });
    const created = await handler(
      request(
        "POST",
        "/Users",
        {
          schemas: ["urn:ietf:params:scim:schemas:core:2.0:User"],
          userName: "ada@acme.test",
        },
        { "x-request-id": "req-1" },
      ),
    );
    expect(created.status).toBe(201);
    await handler(request("GET", "/Users/user-1"));
    const missing = await handler(request("DELETE", "/Users/nobody"));
    expect(missing.status).toBe(404);
    expect(entries).toEqual([
      {
        tenant: "org-a",
        operation: "create",
        resourceType: "User",
        resourceId: "user-1",
        status: 201,
        error: undefined,
        requestId: "req-1",
      },
      {
        tenant: "org-a",
        operation: "delete",
        resourceType: "User",
        resourceId: "nobody",
        status: 404,
        error: "No User nobody",
        requestId: undefined,
      },
    ]);
  });
});

describe("sqlScimStore and sqlScimSyncLog", () => {
  it("skip the database for ids that are not UUIDs", async () => {
    const calls: string[] = [];
    const store = sqlScimStore({
      call: async (_schema, fn) => {
        calls.push(fn);
        return null;
      },
    });
    expect(await store.get("User", "org-a", "nope")).toEqual(ok(undefined));
    expect(await store.delete("Group", "org-a", "nope")).toEqual(ok(false));
    expect(calls).toEqual([]);
  });

  it("writes the log through scim_log_sync", async () => {
    const calls: unknown[] = [];
    const log = sqlScimSyncLog({
      call: async (schema, fn, args) => {
        calls.push([schema, fn, args]);
        return null;
      },
    });
    await log.record({
      tenant: "org-a",
      operation: "patch",
      resourceType: "Group",
      resourceId: "g1",
      status: 200,
      error: undefined,
      requestId: "req-2",
    });
    expect(calls).toEqual([
      [
        "better_supabase",
        "scim_log_sync",
        {
          tenant: "org-a",
          operation: "patch",
          resource_type: "Group",
          resource_id: "g1",
          status: 200,
          error: null,
          request_id: "req-2",
        },
      ],
    ]);
  });
});

describe("scimHandler errors", () => {
  const USER = ["urn:ietf:params:scim:schemas:core:2.0:User"];
  const GROUP = ["urn:ietf:params:scim:schemas:core:2.0:Group"];

  function failingStore(kind: "not_found" | "stale" | "unexpected") {
    const { store } = pushDownStore();
    return {
      ...store,
      save: async () => err(dbError(kind, "Store says no")),
    } satisfies ScimStore;
  }

  it.each([
    ["not_found", 404],
    ["stale", 412],
    ["unexpected", 500],
  ] as const)("maps a %s save to %i", async (kind, status) => {
    const handler = scimHandler({
      store: failingStore(kind),
      keys,
      basePath: "/scim/v2",
    });
    const response = await handler(
      request("POST", "/Users", { schemas: USER, userName: "ada@acme.test" }),
    );
    expect(response.status).toBe(status);
  });

  it.each([
    [
      "a userName that is not a string",
      "/Users",
      { schemas: USER, userName: 7 },
    ],
    [
      "an active that is not a boolean",
      "/Users",
      { schemas: USER, userName: "ada@acme.test", active: "yes" },
    ],
    [
      "emails that are not objects",
      "/Users",
      { schemas: USER, userName: "ada@acme.test", emails: ["ada@acme.test"] },
    ],
    ["a group without a displayName", "/Groups", { schemas: GROUP }],
    ["a body that is not an object", "/Users", ["not", "an", "object"]],
  ])("rejects %s with 400", async (_name, path, body) => {
    const { store } = pushDownStore();
    const handler = scimHandler({ store, keys, basePath: "/scim/v2" });
    expect((await handler(request("POST", path, body))).status).toBe(400);
  });

  it("answers stale If-Match, wrong methods and unknown paths", async () => {
    const { store } = pushDownStore();
    const handler = scimHandler({ store, keys, basePath: "/scim/v2" });
    await handler(
      request("POST", "/Users", { schemas: USER, userName: "ada@acme.test" }),
    );
    const stale = await handler(
      request(
        "PATCH",
        "/Users/user-1",
        {
          schemas: ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
          Operations: [{ op: "replace", path: "active", value: false }],
        },
        { "if-match": 'W/"9"' },
      ),
    );
    expect(stale.status).toBe(412);
    expect((await handler(request("GET", "/Users/.search"))).status).toBe(405);
    expect((await handler(request("PATCH", "/Users"))).status).toBe(405);
    expect((await handler(request("GET", "/Nothing"))).status).toBe(404);
    expect((await handler(request("DELETE", "/Users/user-1"))).status).toBe(
      204,
    );
    expect((await handler(request("DELETE", "/Users/user-1"))).status).toBe(
      404,
    );
  });
});
