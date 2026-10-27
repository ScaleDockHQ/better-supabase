import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it } from "vitest";

import type { AuthorizationRequest } from "../../src/core/authorizer.ts";

import { defineAuthorizer } from "../../src/core/authorizer.ts";
import { DbException, dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import {
  formDataObject,
  hasRole,
  requireCaller,
  rolesAt,
  runAction,
} from "../../src/server/kit.ts";
import { authAs, USER } from "../fixtures/test-server.ts";

const Title: StandardSchemaV1<unknown, { title: string }> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) =>
      typeof value === "object" &&
      value !== null &&
      "title" in value &&
      typeof value.title === "string"
        ? { value: { title: value.title } }
        : { issues: [{ message: "title is required", path: ["title"] }] },
  },
};

describe("formDataObject", () => {
  it("turns repeated keys into arrays", () => {
    const form = new FormData();
    form.append("title", "Hello");
    form.append("tag", "a");
    form.append("tag", "b");
    expect(formDataObject(form)).toEqual({ title: "Hello", tag: ["a", "b"] });
  });
});

describe("rolesAt and hasRole", () => {
  it("reads one role or an array of roles at a claim path", async () => {
    expect(
      rolesAt({ app_metadata: { role: "admin" } }, "app_metadata.role"),
    ).toEqual(["admin"]);
    expect(
      rolesAt({ app_metadata: { roles: ["a", 1, "b"] } }, "app_metadata.roles"),
    ).toEqual(["a", "b"]);
    expect(rolesAt(undefined, "app_metadata.role")).toEqual([]);

    expect(hasRole(await authAs({ role: "admin" }), ["admin"])).toBe(true);
    expect(hasRole(await authAs({ role: "member" }), ["admin"])).toBe(false);
    expect(
      hasRole(
        await authAs({ roles: ["support"] }),
        ["support"],
        "app_metadata.roles",
      ),
    ).toBe(true);
    expect(hasRole(await authAs(), ["admin"])).toBe(false);
  });
});

describe("requireCaller", () => {
  it("returns the session and tenant, or the refusal", async () => {
    const user = await authAs({ role: "member" });
    const caller = await requireCaller(user, {}, "acme");
    expect(caller).toMatchObject({ tenant: "acme" });

    expect(await requireCaller(await authAs(), {}, undefined)).toMatchObject({
      kind: "unauthorized",
    });
    expect(
      await requireCaller(user, { requireTenant: true }, undefined),
    ).toMatchObject({ kind: "forbidden", code: "NO_TENANT" });
    expect(
      await requireCaller(user, { authorize: () => false }, "acme"),
    ).toMatchObject({ kind: "forbidden", code: "NOT_AUTHORIZED" });
  });

  it("admits only the listed roles, at roleClaim when given", async () => {
    const member = await authAs({ role: "member" });
    expect(
      await requireCaller(member, { roles: ["admin"] }, undefined),
    ).toMatchObject({ kind: "forbidden", code: "MISSING_ROLE" });
    expect(
      await requireCaller(member, { roles: ["admin", "member"] }, undefined),
    ).toMatchObject({ tenant: undefined });
    const support = await authAs({ roles: ["support"] });
    expect(
      await requireCaller(
        support,
        { roles: ["support"], roleClaim: "app_metadata.roles" },
        undefined,
      ),
    ).not.toHaveProperty("kind");
  });
});

describe("runAction", () => {
  it("validates FormData input and unwraps Results", async () => {
    const user = await authAs({ role: "member" });
    const form = new FormData();
    form.append("title", "Hello");

    const result = await runAction(
      user,
      { input: Title },
      form,
      undefined,
      (parsed, caller) =>
        ok({
          parsed,
          sub: caller.session.kind === "user" ? caller.session.user.id : null,
        }),
    );

    expect(result).toEqual({
      ok: true,
      data: { parsed: { title: "Hello" }, sub: USER },
      error: null,
    });
  });

  it("returns validation, guard and body errors as data", async () => {
    const user = await authAs({ role: "member" });

    const invalid = await runAction(
      user,
      { input: Title },
      {},
      undefined,
      () => 1,
    );

    expect(invalid).toMatchObject({ ok: false, error: { kind: "validation" } });

    const anonymous = await runAction(
      await authAs(),
      {},
      {},
      undefined,
      () => 1,
    );

    expect(anonymous).toMatchObject({
      ok: false,
      error: { kind: "unauthorized" },
    });

    const failed = await runAction(user, {}, {}, undefined, () =>
      err(dbError("conflict", "Taken")),
    );

    expect(failed).toMatchObject({ ok: false, error: { kind: "conflict" } });

    const thrown = await runAction(user, {}, {}, undefined, () => {
      throw new DbException(dbError("not_found", "Gone"));
    });

    expect(thrown).toMatchObject({ ok: false, error: { kind: "not_found" } });
  });

  it("lets other throws through, so framework redirects keep working", async () => {
    const user = await authAs({ role: "member" });
    await expect(
      runAction(user, {}, {}, undefined, () => {
        throw new Error("redirect");
      }),
    ).rejects.toThrow("redirect");
  });
});

describe("permission", () => {
  it("asks the authorizer after roles and before authorize", async () => {
    const requests: AuthorizationRequest[] = [];

    const authorizer = defineAuthorizer({
      name: "test",
      key: (ref: string) => ref,
      evaluate: (request) => {
        requests.push(request);

        return request.action === "posts.create"
          ? { outcome: "granted" }
          : { outcome: "denied" };
      },
    });

    const user = await authAs({ role: "member" });
    let authorized = 0;

    const granted = await runAction(
      user,
      {
        input: Title,
        permission: "posts.create",
        authorize: () => {
          authorized += 1;

          return true;
        },
      },
      { title: "Hi" },
      "o1",
      () => ok("done"),
      authorizer,
    );

    expect(granted).toMatchObject({ ok: true, data: "done" });
    expect(authorized).toBe(1);
    expect(requests[0]).toMatchObject({
      subject: { type: "user", id: USER },
      action: "posts.create",
      resource: { type: "action", properties: { title: "Hi" } },
      context: { tenant: "o1" },
    });

    const denied = await requireCaller(
      user,
      { permission: "posts.delete", authorize: () => true },
      undefined,
      authorizer,
    );

    expect(denied).toMatchObject({
      kind: "forbidden",
      code: "PERMISSION_DENIED",
    });
    expect(requests[1]?.resource).toEqual({ type: "route" });

    const roles = await requireCaller(
      user,
      { roles: ["admin"], permission: "posts.create" },
      undefined,
      authorizer,
    );

    expect(roles).toMatchObject({ code: "MISSING_ROLE" });
    expect(requests).toHaveLength(2);
  });

  it("refuses a declared permission without an authorizer", async () => {
    const caller = await requireCaller(
      await authAs({ role: "member" }),
      { permission: "posts.create" },
      undefined,
    );

    expect(caller).toMatchObject({
      kind: "forbidden",
      code: "PERMISSION_DENIED",
    });
  });
});

describe("resource", () => {
  const owners = new Map([["p1", USER]]);

  const ownerOnly = defineAuthorizer({
    name: "owner",
    key: (ref: string) => ref,
    evaluate: (request) =>
      request.resource.properties?.["ownerId"] === request.subject.id
        ? { outcome: "granted" }
        : { outcome: "denied" },
  });

  const Project: StandardSchemaV1<unknown, { id: string }> = {
    "~standard": {
      version: 1,
      vendor: "test",
      validate: (value) =>
        typeof value === "object" &&
        value !== null &&
        "id" in value &&
        typeof value.id === "string"
          ? { value: { id: value.id } }
          : { issues: [{ message: "id is required" }] },
    },
  };

  const load = (input: unknown) => {
    const id =
      typeof input === "object" && input !== null && "id" in input
        ? String(input.id)
        : "";

    const ownerId = owners.get(id);

    if (ownerId === undefined) {
      throw new DbException(dbError("not_found", "No such project"));
    }

    return { type: "project", id, properties: { ownerId } };
  };

  it("checks the permission against the loaded resource", async () => {
    const user = await authAs({ role: "member" });
    const seen: unknown[] = [];

    const granted = await runAction(
      user,
      {
        input: Project,
        permission: "projects.update",
        resource: (input, ctx) => {
          seen.push(ctx);

          return load(input);
        },
      },
      { id: "p1" },
      "o1",
      () => ok("saved"),
      ownerOnly,
      { db: "the db" },
    );

    expect(granted).toMatchObject({ ok: true, data: "saved" });
    expect(seen).toEqual([
      {
        db: "the db",
        session: expect.objectContaining({ user: expect.anything() }),
        tenant: "o1",
      },
    ]);
  });

  it("refuses when the authorizer denies the loaded resource", async () => {
    owners.set("p2", "someone-else");

    const denied = await runAction(
      await authAs({ role: "member" }),
      { input: Project, permission: "projects.update", resource: load },
      { id: "p2" },
      undefined,
      () => ok("saved"),
      ownerOnly,
    );

    expect(denied.error).toMatchObject({
      kind: "forbidden",
      code: "PERMISSION_DENIED",
    });
  });

  it("refuses when the loader throws, keeping a DbException's error", async () => {
    const user = await authAs({ role: "member" });

    const missing = await runAction(
      user,
      { input: Project, permission: "projects.update", resource: load },
      { id: "nope" },
      undefined,
      () => ok("saved"),
      ownerOnly,
    );

    expect(missing.error).toMatchObject({ kind: "not_found" });

    const broken = await requireCaller(
      user,
      {
        permission: "projects.read",
        resource: () => {
          throw new Error("connection reset");
        },
      },
      undefined,
      ownerOnly,
    );

    expect(broken).toMatchObject({
      kind: "forbidden",
      code: "RESOURCE_UNAVAILABLE",
    });
  });

  it("runs no loader without a permission", async () => {
    let loaded = 0;

    const caller = await requireCaller(
      await authAs({ role: "member" }),
      {
        resource: () => {
          loaded += 1;

          return { type: "project" };
        },
      },
      undefined,
    );

    expect(caller).toMatchObject({ session: expect.anything() });
    expect(loaded).toBe(0);
  });
});
