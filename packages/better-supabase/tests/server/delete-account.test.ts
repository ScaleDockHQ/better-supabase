import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expect, it, vi } from "vitest";

import type { MutationNotice } from "../../src/core/events.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { deleteAccount } from "../../src/server/delete-account.ts";
import { defineBucket } from "../../src/storage/index.ts";
import { fakeStorage, storageError } from "../fixtures/fake-storage.ts";
import { schema } from "../fixtures/generated-camel.ts";

const USER = "u1";
const OTHER = "u2";

const documents = defineBucket({
  id: "documents",
  path: "{userId}/{file}",
  policy: "owner",
});
const shared = defineBucket({ id: "shared", path: "{orgId}/{userId}/{file}" });
const logos = defineBucket({ id: "logos", path: "{orgId}/{file}" });
const avatars = defineBucket({
  id: "avatars",
  path: "people/{memberId}/{file}",
  policy: "owner",
  owner: { param: "memberId" },
});

type DeleteUser = (id: string) => Promise<{ error: unknown }>;

function setup(
  options: {
    files?: Record<string, string>;
    deleteUser?: DeleteUser;
    fail?: NonNullable<Parameters<typeof fakeStorage>[0]>["fail"];
  } = {},
) {
  const storage = fakeStorage({
    files: options.files ?? {},
    ...(options.fail ? { fail: options.fail } : {}),
  });
  const deleteUser = vi.fn<DeleteUser>(
    options.deleteUser ?? (async () => ({ error: null })),
  );
  // SAFETY: deleteAccount reads `storage` and `auth.admin.deleteUser` only.
  const client = {
    storage: storage.client.storage,
    auth: { admin: { deleteUser } },
  } as unknown as SupabaseClient;
  const sb = defineSupabase(schema);
  const notices: MutationNotice[] = [];
  sb.on("mutation", (notice) => notices.push(notice));
  return { sb, storage, deleteUser, notices, service: () => client };
}

describe("deleteAccount", () => {
  it("removes the user's objects, deletes the user and announces it", async () => {
    const { sb, storage, deleteUser, notices, service } = setup({
      files: {
        [`documents/${USER}/a.txt`]: "a",
        [`documents/${USER}/b.txt`]: "b",
        [`documents/${OTHER}/a.txt`]: "a",
        [`shared/o1/${USER}/c.txt`]: "c",
        [`shared/o1/${OTHER}/c.txt`]: "c",
        [`shared/o1/${USER}/deep/d.txt`]: "d",
        "logos/o1/logo.png": "l",
        [`avatars/people/${USER}/me.png`]: "m",
      },
    });
    const context = { actor: { id: "admin", kind: "user" as const } };
    const result = await deleteAccount(sb, service, USER, {
      buckets: [documents, shared, logos, avatars],
      cascades: ["customers", "notes"],
      context,
    });

    expect(result).toEqual({
      ok: true,
      data: {
        userId: USER,
        removed: { documents: 2, shared: 1, avatars: 1 },
      },
      error: null,
    });
    expect([...storage.files.keys()].toSorted()).toEqual([
      `documents/${OTHER}/a.txt`,
      "logos/o1/logo.png",
      `shared/o1/${USER}/deep/d.txt`,
      `shared/o1/${OTHER}/c.txt`,
    ]);
    expect(storage.calls.some((call) => call.bucket === "logos")).toBe(false);
    expect(deleteUser).toHaveBeenCalledWith(USER);
    expect(notices.map(({ table, kind, rows }) => [table, kind, rows])).toEqual(
      [
        ["auth.users", "delete", [{ id: USER }]],
        ["customers", "delete", []],
        ["notes", "delete", []],
      ],
    );
    expect(notices.every((notice) => notice.context === context)).toBe(true);
  });

  it("removes objects in batches of 1000", async () => {
    const files: Record<string, string> = {};
    for (let index = 0; index < 1001; index += 1)
      files[`documents/${USER}/${String(index).padStart(4, "0")}.txt`] = "x";
    const { sb, storage, service } = setup({ files });
    const result = await deleteAccount(sb, service, USER, {
      buckets: [documents],
    });
    expect(result.ok && result.data.removed).toEqual({ documents: 1001 });
    const removes = storage.calls.filter((call) => call.method === "remove");
    expect(removes.map((call) => (call.args[0] as string[]).length)).toEqual([
      1000, 1,
    ]);
    expect(storage.files.size).toBe(0);
  });

  it("works without buckets and uses an empty context", async () => {
    const { sb, deleteUser, notices, service } = setup();
    expect(await deleteAccount(sb, service, USER)).toEqual({
      ok: true,
      data: { userId: USER, removed: {} },
      error: null,
    });
    expect(deleteUser).toHaveBeenCalledOnce();
    expect(notices).toHaveLength(1);
    expect(notices[0]?.context).toEqual({});
  });

  it("stops before deleting the user when listing fails", async () => {
    const { sb, deleteUser, notices, service } = setup({
      fail: { list: storageError("denied", { statusCode: "403" }) },
    });
    const result = await deleteAccount(sb, service, USER, {
      buckets: [documents],
    });
    expect(result).toMatchObject({
      ok: false,
      error: { kind: "forbidden", table: "documents" },
    });
    expect(deleteUser).not.toHaveBeenCalled();
    expect(notices).toEqual([]);
  });

  it("stops before deleting the user when removing fails", async () => {
    const { sb, deleteUser, service } = setup({
      files: { [`documents/${USER}/a.txt`]: "a" },
      fail: { remove: storageError("boom", { statusCode: "500" }) },
    });
    const result = await deleteAccount(sb, service, USER, {
      buckets: [documents],
    });
    expect(result).toMatchObject({ ok: false, error: { kind: "network" } });
    expect(deleteUser).not.toHaveBeenCalled();
  });

  it("passes the signal to listing and aborts before work", async () => {
    const { sb, storage, deleteUser, service } = setup({
      files: { [`documents/${USER}/a.txt`]: "a" },
    });
    const controller = new AbortController();
    const ok = await deleteAccount(sb, service, USER, {
      buckets: [documents],
      signal: controller.signal,
    });
    expect(ok.ok).toBe(true);
    expect(storage.calls[0]?.method).toBe("list");

    const aborted = await deleteAccount(sb, service, USER, {
      buckets: [documents],
      signal: AbortSignal.abort(),
    });
    expect(!aborted.ok && aborted.error.kind).toBe("aborted");
    const noBuckets = await deleteAccount(sb, service, USER, {
      signal: AbortSignal.abort(),
    });
    expect(!noBuckets.ok && noBuckets.error.kind).toBe("aborted");
    expect(deleteUser).toHaveBeenCalledOnce();
  });

  it.each([
    [{ code: "user_not_found", message: "User not found" }, "not_found"],
    [{ status: 404, message: "missing" }, "not_found"],
    [{ status: 500, message: "Database error deleting user" }, "conflict"],
    [{ status: 401, message: "no" }, "unauthorized"],
    [{ status: 403, message: "no" }, "forbidden"],
    [{ status: 503, message: "down" }, "network"],
    [{ name: "AuthRetryableFetchError", message: "fetch failed" }, "network"],
    [{ status: 422, message: "odd" }, "unexpected"],
  ] as const)("maps the Auth error %j to %s", async (error, kind) => {
    const { sb, notices, service } = setup({
      deleteUser: async () => ({ error }),
    });
    const result = await deleteAccount(sb, service, USER);
    expect(result).toMatchObject({
      ok: false,
      error: { kind, table: "auth.users", message: error.message },
    });
    expect(notices).toEqual([]);
  });

  it("names BS406 for a foreign key that blocks the delete", async () => {
    const { sb, service } = setup({
      deleteUser: async () => ({
        error: {
          status: 500,
          code: "unexpected_failure",
          message: "Database error deleting user",
        },
      }),
    });
    const result = await deleteAccount(sb, service, USER);
    expect(result).toMatchObject({
      ok: false,
      error: { kind: "conflict", code: "unexpected_failure" },
    });
    expect(!result.ok && result.error.hint).toContain("BS406");
  });

  it("maps a thrown error and passes a DbError through", async () => {
    const thrown = setup({
      deleteUser: () => Promise.reject(new Error("socket hang up")),
    });
    expect(await deleteAccount(thrown.sb, thrown.service, USER)).toMatchObject({
      ok: false,
      error: { kind: "unexpected", message: "socket hang up" },
    });

    const odd = setup({ deleteUser: () => Promise.reject("nope") });
    expect(await deleteAccount(odd.sb, odd.service, USER)).toMatchObject({
      ok: false,
      error: { kind: "unexpected", message: "Auth request failed" },
    });

    const original = dbError("forbidden", "blocked");
    const passthrough = setup({
      deleteUser: async () => ({ error: original }),
    });
    expect(
      await deleteAccount(passthrough.sb, passthrough.service, USER),
    ).toEqual({ ok: false, data: null, error: original });
  });
});
