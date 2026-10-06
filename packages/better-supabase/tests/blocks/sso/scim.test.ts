import { describe, expect, it } from "vitest";

import type { ApiKeyCheck } from "../../../src/blocks/api-keys/api-keys.ts";
import type { BlockTransport } from "../../../src/blocks/sso/index.ts";

import { scimHandler } from "../../../src/blocks/sso/index.ts";
import { AsyncResult, ok } from "../../../src/core/result.ts";

type Row = Record<string, unknown>;

const pgError = (code: string, message: string, hint?: string) =>
  Object.assign(new Error(message), { code, ...(hint ? { hint } : {}) });

/** The scim_* functions over maps, close enough to the SQL for the handler. */
function memoryStore() {
  const users = new Map<string, Row>();
  const groups = new Map<string, Row>();
  const membership = new Map<string, Set<string>>();
  let clock = 0;
  const now = () =>
    new Date(Date.UTC(2026, 9, 6, 12, 0, clock++)).toISOString();

  const userJson = (row: Row): Row => ({
    ...row,
    groups: [...groups.values()]
      .filter((group) =>
        membership.get(String(group["id"]))?.has(String(row["id"])),
      )
      .map((group) => ({ value: group["id"], display: group["display_name"] })),
  });
  const groupJson = (row: Row): Row => ({
    ...row,
    members: [...(membership.get(String(row["id"])) ?? [])].map((id) => ({
      value: id,
      display: users.get(id)?.["display_name"] ?? users.get(id)?.["user_name"],
    })),
  });
  const inTenant = (map: Map<string, Row>, tenant: unknown, id: unknown) => {
    const row = map.get(String(id));
    return row && row["organization_id"] === tenant ? row : undefined;
  };
  const checkVersion = (row: Row, version: unknown) => {
    if (version !== null && version !== row["version"]) {
      throw pgError("P0001", "changed", "SCIM_PRECONDITION");
    }
  };

  const functions: Record<string, (args: Row) => unknown> = {
    scim_list_users: ({ tenant }) =>
      [...users.values()]
        .filter((row) => row["organization_id"] === tenant)
        .map(userJson),
    scim_get_user: ({ tenant, id }) => {
      const row = inTenant(users, tenant, id);
      return row ? userJson(row) : null;
    },
    scim_save_user: ({ tenant, id, data, version }) => {
      const input = data as Row;
      const name = String(input["userName"]).toLowerCase();
      for (const row of users.values()) {
        if (
          row["organization_id"] === tenant &&
          row["id"] !== id &&
          String(row["user_name"]).toLowerCase() === name
        ) {
          throw pgError(
            "23505",
            "duplicate key value violates unique constraint",
          );
        }
      }
      const fields = {
        user_name: input["userName"],
        external_id: input["externalId"],
        display_name: input["displayName"],
        given_name: input["givenName"],
        family_name: input["familyName"],
        emails: input["emails"],
        active: input["active"],
      };
      if (id === null) {
        const created = {
          id: crypto.randomUUID(),
          organization_id: tenant,
          version: 1,
          created_at: now(),
          updated_at: now(),
          ...fields,
        };
        users.set(created.id, created);
        return userJson(created);
      }
      const row = inTenant(users, tenant, id);
      if (!row)
        throw pgError("P0002", "No SCIM user has this id", "SCIM_NOT_FOUND");
      checkVersion(row, version);
      Object.assign(row, fields, {
        version: Number(row["version"]) + 1,
        updated_at: now(),
      });
      return userJson(row);
    },
    scim_delete_user: ({ tenant, id }) => {
      if (!inTenant(users, tenant, id)) return false;
      users.delete(String(id));
      for (const set of membership.values()) set.delete(String(id));
      return true;
    },
    scim_list_groups: ({ tenant }) =>
      [...groups.values()]
        .filter((row) => row["organization_id"] === tenant)
        .map(groupJson),
    scim_get_group: ({ tenant, id }) => {
      const row = inTenant(groups, tenant, id);
      return row ? groupJson(row) : null;
    },
    scim_save_group: ({ tenant, id, data, version }) => {
      const input = data as Row;
      const members = input["members"] as string[];
      for (const member of members) {
        if (!inTenant(users, tenant, member)) {
          throw pgError("22023", "members must be SCIM users", "SCIM_INVALID");
        }
      }
      const fields = {
        display_name: input["displayName"],
        external_id: input["externalId"],
      };
      let row: Row;
      if (id === null) {
        row = {
          id: crypto.randomUUID(),
          organization_id: tenant,
          version: 1,
          created_at: now(),
          updated_at: now(),
          ...fields,
        };
        groups.set(String(row["id"]), row);
      } else {
        const found = inTenant(groups, tenant, id);
        if (!found) throw pgError("P0002", "No SCIM group", "SCIM_NOT_FOUND");
        checkVersion(found, version);
        row = Object.assign(found, fields, {
          version: Number(found["version"]) + 1,
          updated_at: now(),
        });
      }
      membership.set(String(row["id"]), new Set(members));
      return groupJson(row);
    },
    scim_delete_group: ({ tenant, id }) => {
      if (!inTenant(groups, tenant, id)) return false;
      groups.delete(String(id));
      membership.delete(String(id));
      return true;
    },
  };

  const transport: BlockTransport = {
    call(_schema, fn, args) {
      const answer = functions[fn];
      if (!answer) return Promise.reject(new Error(`no fake for ${fn}`));
      try {
        return Promise.resolve(answer({ ...args }));
      } catch (error) {
        return Promise.reject(error);
      }
    },
  };
  return { transport, users, groups };
}

const key = (
  organizationId: string | undefined,
  scopes: readonly string[],
) => ({
  id: "k1",
  organizationId,
  userId: undefined,
  name: "Okta",
  prefix: "bs",
  publicId: "pub",
  scopes,
});

function setup(
  options: {
    readonly keys?: Record<string, ApiKeyCheck>;
    readonly maxResults?: number;
  } = {},
) {
  const store = memoryStore();
  const checks: Record<string, ApiKeyCheck> = options.keys ?? {
    "org-a": { status: "ok", key: key("org-a", ["scim"]) as never },
    "org-b": { status: "ok", key: key("org-b", ["*"]) as never },
  };
  const handler = scimHandler({
    transport: store.transport,
    keys: {
      verify: (token) =>
        AsyncResult.from(async () =>
          ok(checks[token] ?? { status: "invalid" }),
        ),
    },
    basePath: "/scim/v2",
    ...(options.maxResults ? { maxResults: options.maxResults } : {}),
  });
  const send = async (
    method: string,
    path: string,
    body?: unknown,
    init: { token?: string | null; headers?: Record<string, string> } = {},
  ) => {
    const token = init.token === undefined ? "org-a" : init.token;
    const response = await handler(
      new Request(`https://app.test/scim/v2${path}`, {
        method,
        headers: {
          ...(token === null ? {} : { authorization: `Bearer ${token}` }),
          ...(body === undefined
            ? {}
            : { "content-type": "application/scim+json" }),
          ...init.headers,
        },
        ...(body === undefined
          ? {}
          : { body: typeof body === "string" ? body : JSON.stringify(body) }),
      }),
    );
    const text = await response.text();
    return {
      status: response.status,
      headers: response.headers,
      body: (text ? JSON.parse(text) : undefined) as Row & {
        Resources: Row[];
        [key: string]: unknown;
      },
    };
  };
  return { send, store };
}

const USER = "urn:ietf:params:scim:schemas:core:2.0:User";
const GROUP = "urn:ietf:params:scim:schemas:core:2.0:Group";
const PATCH = "urn:ietf:params:scim:api:messages:2.0:PatchOp";
const ERROR = "urn:ietf:params:scim:api:messages:2.0:Error";

const bjensen = {
  schemas: [USER],
  userName: "bjensen@acme.test",
  externalId: "00u1",
  name: { givenName: "Barbara", familyName: "Jensen" },
  emails: [{ value: "bjensen@acme.test", type: "work", primary: true }],
  active: true,
};

describe("scimHandler", () => {
  it("creates a user with Location, meta and an ETag", async () => {
    const { send } = setup();
    const created = await send("POST", "/Users", bjensen);
    expect(created.status).toBe(201);
    expect(created.headers.get("content-type")).toBe("application/scim+json");
    const id = String(created.body["id"]);
    expect(created.headers.get("location")).toBe(
      `https://app.test/scim/v2/Users/${id}`,
    );
    expect(created.headers.get("etag")).toBe('W/"1"');
    expect(created.body).toMatchObject({
      schemas: [USER],
      userName: "bjensen@acme.test",
      externalId: "00u1",
      name: {
        givenName: "Barbara",
        familyName: "Jensen",
        formatted: "Barbara Jensen",
      },
      active: true,
      groups: [],
      meta: {
        resourceType: "User",
        location: `https://app.test/scim/v2/Users/${id}`,
        version: 'W/"1"',
      },
    });
  });

  it("answers 409 uniqueness for a duplicate userName", async () => {
    const { send } = setup();
    await send("POST", "/Users", bjensen);
    const duplicate = await send("POST", "/Users", {
      ...bjensen,
      userName: "BJensen@acme.test",
    });
    expect(duplicate.status).toBe(409);
    expect(duplicate.body).toEqual({
      schemas: [ERROR],
      status: "409",
      scimType: "uniqueness",
      detail: "A resource with this value exists",
    });
  });

  it("filters, pages and projects list responses", async () => {
    const { send } = setup({ maxResults: 2 });
    for (const name of ["a", "b", "c"]) {
      await send("POST", "/Users", {
        schemas: [USER],
        userName: `${name}@acme.test`,
        emails: [
          { value: `${name}@acme.test`, type: name === "c" ? "home" : "work" },
        ],
        active: name !== "b",
      });
    }
    const all = await send("GET", "/Users?count=10");
    expect(all.body).toMatchObject({
      totalResults: 3,
      itemsPerPage: 2,
      startIndex: 1,
    });
    const second = await send("GET", "/Users?startIndex=3");
    expect(second.body.Resources.map((r) => r["userName"])).toEqual([
      "c@acme.test",
    ]);

    const filtered = await send(
      "GET",
      `/Users?filter=${encodeURIComponent('userName eq "A@ACME.TEST" or (active eq false and emails[type eq "work"])')}`,
    );
    expect(filtered.body.Resources.map((r) => r["userName"])).toEqual([
      "a@acme.test",
      "b@acme.test",
    ]);
    const projected = await send("GET", "/Users?attributes=userName&count=1");
    expect(Object.keys(projected.body.Resources[0]!).toSorted()).toEqual([
      "id",
      "schemas",
      "userName",
    ]);
    const none = await send(
      "GET",
      `/Users?filter=${encodeURIComponent('userName eq "nobody"')}`,
    );
    expect(none.status).toBe(200);
    expect(none.body).toMatchObject({ totalResults: 0, Resources: [] });
    const search = await send("POST", "/Users/.search", {
      schemas: ["urn:ietf:params:scim:api:messages:2.0:SearchRequest"],
      filter: 'emails.type eq "home"',
      excludedAttributes: ["emails"],
    });
    expect(search.body.Resources).toHaveLength(1);
    expect(search.body.Resources[0]!["emails"]).toBeUndefined();
  });

  it("answers 400 invalidFilter for unknown operators and bad syntax", async () => {
    const { send } = setup();
    for (const filter of [
      'userName xx "a"',
      'userName eq "a" and',
      "active gt true",
    ]) {
      await send("POST", "/Users", { schemas: [USER], userName: "a" });
      const response = await send(
        "GET",
        `/Users?filter=${encodeURIComponent(filter)}`,
      );
      expect(response.status).toBe(400);
      expect(response.body["scimType"]).toBe("invalidFilter");
    }
  });

  it("patches atomically and keeps the original on a failed operation", async () => {
    const { send } = setup();
    const created = await send("POST", "/Users", bjensen);
    const id = String(created.body["id"]);
    const failed = await send("PATCH", `/Users/${id}`, {
      schemas: [PATCH],
      Operations: [
        { op: "replace", path: "displayName", value: "Babs" },
        { op: "replace", path: 'emails[type eq "home"].value', value: "x@y" },
      ],
    });
    expect(failed.status).toBe(400);
    expect(failed.body["scimType"]).toBe("noTarget");
    const unchanged = await send("GET", `/Users/${id}`);
    expect(unchanged.body["displayName"]).toBeUndefined();

    const patched = await send("PATCH", `/Users/${id}`, {
      schemas: [PATCH],
      Operations: [
        { op: "Replace", value: { active: "False", "name.givenName": "Babs" } },
        {
          op: "add",
          path: "emails",
          value: [{ value: "b@home.test", type: "home", primary: true }],
        },
        { op: "replace", path: `${USER}:displayName`, value: "Babs Jensen" },
      ],
    });
    expect(patched.status).toBe(200);
    expect(patched.body).toMatchObject({
      active: false,
      displayName: "Babs Jensen",
      name: { givenName: "Babs", familyName: "Jensen" },
      emails: [
        { value: "bjensen@acme.test", type: "work" },
        { value: "b@home.test", type: "home", primary: true },
      ],
      meta: { version: 'W/"2"' },
    });
    expect(patched.headers.get("etag")).toBe('W/"2"');

    const removed = await send("PATCH", `/Users/${id}`, {
      schemas: [PATCH],
      Operations: [{ op: "remove", path: 'emails[type eq "home"]' }],
    });
    expect((removed.body["emails"] as Row[]).map((e) => e["value"])).toEqual([
      "bjensen@acme.test",
    ]);
  });

  it.each([
    [{ op: "remove" }, "noTarget"],
    [{ op: "remove", path: "userName" }, "mutability"],
    [{ op: "replace", path: "groups", value: [] }, "mutability"],
    [{ op: "replace", path: "nickName", value: "x" }, "invalidPath"],
    [{ op: "replace", path: "name.middle", value: "x" }, "invalidPath"],
    [
      { op: "replace", path: "displayName[value eq 1]", value: "x" },
      "invalidPath",
    ],
    [
      { op: "replace", path: 'emails[type xx "a"]', value: "x" },
      "invalidFilter",
    ],
    [{ op: "move", path: "displayName" }, "invalidSyntax"],
    [{ op: "add", value: "x" }, "invalidValue"],
  ])("rejects the PATCH operation %j with %s", async (operation, scimType) => {
    const { send } = setup();
    const id = String((await send("POST", "/Users", bjensen)).body["id"]);
    const response = await send("PATCH", `/Users/${id}`, {
      schemas: [PATCH],
      Operations: [operation],
    });
    expect(response.status).toBe(400);
    expect(response.body["scimType"]).toBe(scimType);
  });

  it("honors If-Match and If-None-Match", async () => {
    const { send } = setup();
    const id = String((await send("POST", "/Users", bjensen)).body["id"]);
    const cached = await send("GET", `/Users/${id}`, undefined, {
      headers: { "if-none-match": 'W/"1"' },
    });
    expect(cached.status).toBe(304);
    const stale = await send(
      "PUT",
      `/Users/${id}`,
      { ...bjensen, displayName: "x" },
      { headers: { "if-match": 'W/"7"' } },
    );
    expect(stale.status).toBe(412);
    const fresh = await send(
      "PUT",
      `/Users/${id}`,
      { ...bjensen, displayName: "x" },
      { headers: { "if-match": 'W/"1"' } },
    );
    expect(fresh.status).toBe(200);
    expect(fresh.body["displayName"]).toBe("x");
  });

  it("deletes, then answers 404 for the user", async () => {
    const { send } = setup();
    const id = String((await send("POST", "/Users", bjensen)).body["id"]);
    expect((await send("DELETE", `/Users/${id}`)).status).toBe(204);
    for (const method of ["GET", "DELETE", "PATCH"]) {
      const response = await send(
        method,
        `/Users/${id}`,
        method === "PATCH" ? { schemas: [PATCH], Operations: [] } : undefined,
      );
      expect(response.status).toBe(404);
    }
    expect((await send("PUT", "/Users/not-a-uuid", bjensen)).status).toBe(404);
  });

  it("keeps each token to its organization", async () => {
    const { send } = setup();
    const id = String((await send("POST", "/Users", bjensen)).body["id"]);
    expect(
      (await send("GET", `/Users/${id}`, undefined, { token: "org-b" })).status,
    ).toBe(404);
    const other = await send("GET", "/Users", undefined, { token: "org-b" });
    expect(other.body["totalResults"]).toBe(0);
  });

  it("manages groups and their members", async () => {
    const { send } = setup();
    const a = String((await send("POST", "/Users", bjensen)).body["id"]);
    const b = String(
      (
        await send("POST", "/Users", {
          schemas: [USER],
          userName: "jsmith@acme.test",
        })
      ).body["id"],
    );
    const group = await send("POST", "/Groups", {
      schemas: [GROUP],
      displayName: "Admins",
      members: [{ value: a }],
    });
    expect(group.status).toBe(201);
    const gid = String(group.body["id"]);
    expect(group.body["members"]).toEqual([
      {
        value: a,
        display: "bjensen@acme.test",
        type: "User",
        $ref: `https://app.test/scim/v2/Users/${a}`,
      },
    ]);
    const added = await send("PATCH", `/Groups/${gid}`, {
      schemas: [PATCH],
      Operations: [
        { op: "add", path: "members", value: [{ value: b }, { value: a }] },
      ],
    });
    expect(
      (added.body["members"] as Row[])
        .map((m) => String(m["value"]))
        .toSorted((x, y) => x.localeCompare(y)),
    ).toEqual([a, b].toSorted((x, y) => x.localeCompare(y)));
    const user = await send("GET", `/Users/${b}`);
    expect(user.body["groups"]).toEqual([
      {
        value: gid,
        display: "Admins",
        $ref: `https://app.test/scim/v2/Groups/${gid}`,
      },
    ]);
    const removed = await send("PATCH", `/Groups/${gid}`, {
      schemas: [PATCH],
      Operations: [
        { op: "remove", path: "members", value: [{ value: a }] },
        { op: "remove", path: `members[value eq "${b}"]` },
      ],
    });
    expect(removed.body["members"]).toEqual([]);
    const unknown = await send("PATCH", `/Groups/${gid}`, {
      schemas: [PATCH],
      Operations: [
        { op: "add", path: "members", value: [{ value: crypto.randomUUID() }] },
      ],
    });
    expect(unknown.status).toBe(400);
    expect(unknown.body["scimType"]).toBe("invalidValue");
    expect((await send("DELETE", `/Groups/${gid}`)).status).toBe(204);
    expect((await send("GET", `/Groups/${gid}`)).status).toBe(404);
  });

  it("serves discovery without a token and refuses filters there", async () => {
    const { send } = setup();
    const config = await send("GET", "/ServiceProviderConfig", undefined, {
      token: null,
    });
    expect(config.status).toBe(200);
    expect(config.body).toMatchObject({
      patch: { supported: true },
      bulk: { supported: false },
      filter: { supported: true, maxResults: 100 },
      etag: { supported: true },
      authenticationSchemes: [{ type: "oauthbearertoken" }],
    });
    const types = await send("GET", "/ResourceTypes", undefined, {
      token: null,
    });
    expect(types.body.Resources.map((r) => r["endpoint"])).toEqual([
      "/Users",
      "/Groups",
    ]);
    const schema = await send("GET", `/Schemas/${USER}`, undefined, {
      token: null,
    });
    expect(schema.body["id"]).toBe(USER);
    expect(
      (await send("GET", "/Schemas/urn:nope", undefined, { token: null }))
        .status,
    ).toBe(404);
    expect(
      (await send("GET", "/Schemas?filter=x", undefined, { token: null }))
        .status,
    ).toBe(403);
    expect((await send("POST", "/Schemas", {}, { token: null })).status).toBe(
      405,
    );
  });

  it("authenticates every resource request", async () => {
    const { send } = setup({
      keys: {
        personal: { status: "ok", key: key(undefined, ["scim"]) as never },
        narrow: { status: "ok", key: key("org-a", ["read"]) as never },
        busy: { status: "rate_limited", retryAfter: 30 },
      },
    });
    const missing = await send("GET", "/Users", undefined, { token: null });
    expect(missing.status).toBe(401);
    expect(missing.headers.get("www-authenticate")).toBe('Bearer realm="SCIM"');
    expect(
      (await send("GET", "/Users", undefined, { token: "nope" })).status,
    ).toBe(401);
    expect(
      (await send("GET", "/Users", undefined, { token: "personal" })).status,
    ).toBe(403);
    expect(
      (await send("GET", "/Users", undefined, { token: "narrow" })).status,
    ).toBe(403);
    const busy = await send("GET", "/Users", undefined, { token: "busy" });
    expect(busy.status).toBe(429);
    expect(busy.headers.get("retry-after")).toBe("30");
  });

  it("answers other routes and bad bodies with SCIM errors", async () => {
    const { send } = setup();
    expect((await send("GET", "/Me")).status).toBe(501);
    expect((await send("POST", "/Bulk", {})).status).toBe(501);
    expect((await send("GET", "/Widgets")).status).toBe(404);
    expect((await send("GET", "/Users/a/b")).status).toBe(404);
    expect((await send("DELETE", "/Users")).status).toBe(405);
    const syntax = await send("POST", "/Users", "{not json");
    expect(syntax.body).toMatchObject({
      status: "400",
      scimType: "invalidSyntax",
    });
    const schemaless = await send("POST", "/Users", { userName: "x" });
    expect(schemaless.body["scimType"]).toBe("invalidSyntax");
    const nameless = await send("POST", "/Users", { schemas: [USER] });
    expect(nameless.body["scimType"]).toBe("invalidValue");
    const both = await send(
      "GET",
      "/Users?attributes=userName&excludedAttributes=emails",
    );
    expect(both.body["scimType"]).toBe("invalidSyntax");
  });
});
