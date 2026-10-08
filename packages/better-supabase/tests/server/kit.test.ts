import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it } from "vitest";

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
