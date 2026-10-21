import { describe, expect, it, vi } from "vitest";

import type { DbErrorKind } from "../../src/core/errors.ts";
import type {
  CrudEntryLike,
  CrudQueueLike,
} from "../../src/powersync/connector.ts";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";
import {
  createUploadConnector,
  uploadOutcome,
  uploadRoute,
} from "../../src/powersync/connector.ts";

function queue(crud: CrudEntryLike[]) {
  const complete = vi.fn(async () => undefined);
  const limits: (number | undefined)[] = [];

  const db: CrudQueueLike = {
    getCrudBatch: async (limit) => {
      limits.push(limit);

      return crud.length === 0 ? null : { crud, complete };
    },
  };

  return { db, complete, limits };
}

function repository(failWith?: DbErrorKind) {
  const calls: unknown[] = [];

  const reply = () =>
    new AsyncResult(
      Promise.resolve(
        failWith ? err(dbError(failWith, failWith)) : ok({ id: "x" }),
      ),
    );

  return {
    calls,
    repo: {
      upsert: (row: { id: string; name?: string }) => {
        calls.push(["upsert", row]);

        return reply();
      },
      update: (id: string, patch: { name?: string }) => {
        calls.push(["update", id, patch]);

        return reply();
      },
      delete: (id: string) => {
        calls.push(["delete", id]);

        return reply();
      },
    },
  };
}

function session(token: string | null, expiresAt?: number) {
  return {
    auth: {
      getSession: vi.fn(async () => ({
        data: {
          session:
            token === null
              ? null
              : {
                  access_token: token,
                  ...(expiresAt ? { expires_at: expiresAt } : {}),
                },
        },
      })),
    },
  };
}

const put = (
  id: string,
  opData: Record<string, unknown> = {},
): CrudEntryLike => ({ op: "PUT", table: "customers", id, opData });

describe("createUploadConnector", () => {
  it("fetches credentials from the session", async () => {
    const connector = createUploadConnector({
      endpoint: "https://ps.example",
      supabase: session("jwt", 1_800_000_000),
      tables: {},
    });

    expect(await connector.fetchCredentials()).toEqual({
      endpoint: "https://ps.example",
      token: "jwt",
      expiresAt: new Date(1_800_000_000_000),
    });

    const signedOut = createUploadConnector({
      endpoint: "https://ps.example",
      supabase: session(null),
      tables: {},
    });

    expect(await signedOut.fetchCredentials()).toBeNull();
  });

  it("reports a session error to onError and returns no credentials", async () => {
    const onError = vi.fn();

    const failing = (
      getSession: Parameters<
        typeof createUploadConnector
      >[0]["supabase"]["auth"]["getSession"],
    ) =>
      createUploadConnector({
        endpoint: "e",
        supabase: { auth: { getSession } },
        tables: {},
        onError,
      });

    const refused = failing(async () => ({
      data: { session: null },
      error: { name: "AuthApiError", message: "refresh token revoked" },
    }));

    expect(await refused.fetchCredentials()).toBeNull();
    expect(onError).toHaveBeenLastCalledWith(
      expect.objectContaining({
        kind: "unauthorized",
        message: "refresh token revoked",
      }),
      { phase: "credentials" },
    );

    const offline = failing(async () => {
      throw new TypeError("fetch failed");
    });

    expect(await offline.fetchCredentials()).toBeNull();
    expect(onError).toHaveBeenLastCalledWith(
      expect.objectContaining({ kind: "network", message: "fetch failed" }),
      { phase: "credentials" },
    );

    const retryable = failing(async () => ({
      data: { session: null },
      error: { name: "AuthRetryableFetchError", message: "offline" },
    }));

    expect(await retryable.fetchCredentials()).toBeNull();
    expect(onError).toHaveBeenLastCalledWith(
      expect.objectContaining({ kind: "network" }),
      { phase: "credentials" },
    );
    expect(onError).toHaveBeenCalledTimes(3);
  });

  it("calls no onError for a signed-out session, and reports retried uploads", async () => {
    const onError = vi.fn();

    const signedOut = createUploadConnector({
      endpoint: "e",
      supabase: session(null),
      tables: {},
      onError,
    });

    expect(await signedOut.fetchCredentials()).toBeNull();
    expect(onError).not.toHaveBeenCalled();

    const { repo } = repository("network");

    const connector = createUploadConnector({
      endpoint: "e",
      supabase: session("jwt"),
      tables: { customers: repo },
      onError,
    });

    await expect(connector.uploadData(queue([put("1")]).db)).rejects.toThrow(
      "network",
    );
    expect(onError).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({ kind: "network" }),
      { phase: "upload" },
    );
  });

  it("replays a batch through the repositories and completes it", async () => {
    const { repo, calls } = repository();

    const { db, complete, limits } = queue([
      put("1", { name: "A" }),
      { op: "PATCH", table: "customers", id: "1", opData: { name: "B" } },
      { op: "DELETE", table: "customers", id: "1" },
    ]);

    const connector = createUploadConnector({
      endpoint: "e",
      supabase: session("jwt"),
      tables: { customers: repo },
      batchSize: 10,
    });

    await connector.uploadData(db);
    expect(limits).toEqual([10]);
    expect(calls).toEqual([
      ["upsert", { name: "A", id: "1" }],
      ["update", "1", { name: "B" }],
      ["delete", "1"],
    ]);
    expect(complete).toHaveBeenCalledOnce();
    await connector.uploadData(queue([]).db);
  });

  it("keeps the batch queued on a transient error", async () => {
    const { repo } = repository("network");
    const { db, complete } = queue([put("1")]);

    const connector = createUploadConnector({
      endpoint: "e",
      supabase: session("jwt"),
      tables: { customers: repo },
    });

    await expect(connector.uploadData(db)).rejects.toThrow("network");
    expect(complete).not.toHaveBeenCalled();
  });

  it("stops without retrying when the session is gone", async () => {
    const { repo } = repository("unauthorized");
    const { db, complete } = queue([put("1")]);

    const alive = createUploadConnector({
      endpoint: "e",
      supabase: session("jwt"),
      tables: { customers: repo },
    });

    await expect(alive.uploadData(db)).rejects.toThrow("unauthorized");

    const dead = createUploadConnector({
      endpoint: "e",
      supabase: session(null),
      tables: { customers: repo },
    });

    await dead.uploadData(db);
    expect(complete).not.toHaveBeenCalled();
  });

  it("records conflicts and discarded changes and lets the UI dismiss them", async () => {
    const onConflict = vi.fn();
    const onDiscard = vi.fn();
    const conflicting = repository("conflict");
    const refused = repository("check");

    const { db, complete } = queue([
      put("1"),
      { op: "PUT", table: "notes", id: "2" },
      { op: "MERGE", table: "notes", id: "3" },
    ]);

    const connector = createUploadConnector({
      endpoint: "e",
      supabase: session("jwt"),
      tables: { customers: conflicting.repo, notes: refused.repo },
      onConflict,
      onDiscard,
    });

    const listener = vi.fn();
    const unsubscribe = connector.rejected.subscribe(listener);
    await connector.uploadData(db);
    expect(complete).toHaveBeenCalledOnce();
    const changes = connector.rejected.current();
    expect(
      changes.map((change) => [
        change.entry.id,
        change.outcome,
        change.error.kind,
      ]),
    ).toEqual([
      ["1", "conflict", "conflict"],
      ["2", "discard", "check"],
      ["3", "discard", "unsupported"],
    ]);
    expect(onConflict).toHaveBeenCalledOnce();
    expect(onDiscard).toHaveBeenCalledTimes(2);
    connector.rejected.dismiss(changes[0]);
    expect(connector.rejected.current()).toHaveLength(2);
    connector.rejected.dismiss();
    expect(connector.rejected.current()).toEqual([]);
    expect(listener).toHaveBeenCalledTimes(5);
    unsubscribe();
  });

  it("fails loudly for a table without a route, and takes custom routes and classify", async () => {
    const { db, complete } = queue([put("1")]);

    const connector = createUploadConnector({
      endpoint: "e",
      supabase: session("jwt"),
      tables: {},
    });

    await expect(connector.uploadData(db)).rejects.toThrow(
      /no upload route .*customers/,
    );
    expect(complete).not.toHaveBeenCalled();

    const route = vi.fn(async () => err(dbError("conflict", "newer row")));

    const custom = createUploadConnector({
      endpoint: "e",
      supabase: session("jwt"),
      tables: { customers: route },
      classify: (error) => (error.kind === "conflict" ? "discard" : undefined),
    });

    await custom.uploadData(db);
    expect(route).toHaveBeenCalledWith(put("1"));
    expect(custom.rejected.current()[0]?.outcome).toBe("discard");
  });
});

describe("uploadRoute", () => {
  function inserts(failWith?: DbErrorKind) {
    const calls: unknown[] = [];

    const reply = () =>
      new AsyncResult(
        Promise.resolve(
          failWith ? err(dbError(failWith, failWith)) : ok({ id: "x" }),
        ),
      );

    return {
      calls,
      repo: {
        create: (row: { id: string; name?: string }) => {
          calls.push(["create", row]);

          return reply();
        },
        delete: (id: string) => {
          calls.push(["delete", id]);

          return reply();
        },
      },
    };
  }

  it("replays a repository like a bare route by default", async () => {
    const { repo, calls } = repository();
    const route = uploadRoute(repo);

    expect((await route(put("1", { name: "A" }))).ok).toBe(true);
    await route({ op: "PATCH", table: "customers", id: "1", opData: {} });
    await route({ op: "DELETE", table: "customers", id: "1" });
    expect(calls).toEqual([
      ["upsert", { name: "A", id: "1" }],
      ["update", "1", {}],
      ["delete", "1"],
    ]);
  });

  it("inserts a PUT with put: create, and counts a conflict as applied", async () => {
    const created = inserts();

    const { db, complete } = queue([
      put("1", { name: "A" }),
      { op: "DELETE", table: "customers", id: "1" },
    ]);

    await createUploadConnector({
      endpoint: "e",
      supabase: session("jwt"),
      tables: { customers: uploadRoute(created.repo, { put: "create" }) },
    }).uploadData(db);

    expect(created.calls).toEqual([
      ["create", { name: "A", id: "1" }],
      ["delete", "1"],
    ]);
    expect(complete).toHaveBeenCalledOnce();

    const conflicting = inserts("conflict");
    const onConflict = vi.fn();
    const replayed = queue([put("1")]);

    const connector = createUploadConnector({
      endpoint: "e",
      supabase: session("jwt"),
      tables: { customers: uploadRoute(conflicting.repo, { put: "create" }) },
      onConflict,
    });

    await connector.uploadData(replayed.db);
    expect(replayed.complete).toHaveBeenCalledOnce();
    expect(onConflict).not.toHaveBeenCalled();
    expect(connector.rejected.current()).toEqual([]);
  });

  it("classifies other create errors, and discards a PATCH on a create route", async () => {
    const refused = inserts("check");
    const classify = vi.fn(() => undefined);

    const connector = createUploadConnector({
      endpoint: "e",
      supabase: session("jwt"),
      tables: { customers: uploadRoute(refused.repo, { put: "create" }) },
      classify,
    });

    await connector.uploadData(
      queue([
        put("1"),
        { op: "PATCH", table: "customers", id: "1", opData: { name: "B" } },
      ]).db,
    );

    expect(classify).toHaveBeenCalledTimes(2);
    expect(
      connector.rejected
        .current()
        .map((change) => [change.entry.op, change.outcome, change.error.kind]),
    ).toEqual([
      ["PUT", "discard", "check"],
      ["PATCH", "discard", "unsupported"],
    ]);
    expect(refused.calls).toEqual([["create", { id: "1" }]]);
  });
});

describe("uploadOutcome", () => {
  it("retries transient errors, flags conflicts and discards the rest", () => {
    expect(uploadOutcome("timeout")).toBe("retry");
    expect(uploadOutcome("stale")).toBe("conflict");
    expect(uploadOutcome("forbidden")).toBe("discard");
  });
});
