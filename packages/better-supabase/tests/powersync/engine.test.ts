import { describe, expect, it } from "vitest";

import type { SyncStatusLike } from "../../src/powersync/index.ts";

import { createDataList, dataTarget } from "../../src/bindings/data-hooks.ts";
import { createNativeClient } from "../../src/client/native/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { powersyncEngine } from "../../src/powersync/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createSqlite } from "../fixtures/sqlite.ts";

const betterSupabase = defineSupabase(schema);
const ORG = "00000000-0000-4000-8000-000000000001";

const tick = (): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

/** PowerSync's status and listeners, driven by the test. */
function syncedDatabase() {
  const sqlite = createSqlite(betterSupabase.meta);
  const listeners = new Set<(status: SyncStatusLike) => void>();

  let status: SyncStatusLike = {
    connected: false,
    dataFlowStatus: { uploading: false, downloading: false },
  };

  const db = Object.defineProperties(sqlite.db, {
    currentStatus: { get: () => status },
  }) as typeof sqlite.db & { readonly currentStatus: SyncStatusLike };

  Object.assign(db, {
    registerListener: (listener: {
      statusChanged?: (next: SyncStatusLike) => void;
    }) => {
      const { statusChanged } = listener;

      if (statusChanged === undefined) {
        return () => undefined;
      }

      listeners.add(statusChanged);

      return () => {
        listeners.delete(statusChanged);
      };
    },
  });

  const setStatus = (next: SyncStatusLike): void => {
    status = next;

    for (const listener of listeners) {
      listener(next);
    }
  };

  return { ...sqlite, db, setStatus, listeners };
}

function setup(options: Parameters<typeof powersyncEngine>[1] = {}) {
  const database = syncedDatabase();
  const server = capturingClient(() => ({ body: [] }));
  const engine = powersyncEngine(database.db, options);

  const bsb = createNativeClient(betterSupabase, server.client, { engine });

  return { ...database, server, engine, bsb };
}

describe("powersyncEngine", () => {
  it("runs only the local tables on the device and the rest on the server", async () => {
    const { bsb, server } = setup({ local: ["tags"] });

    await bsb.db.tags.create({ organizationId: ORG, name: "local" }).orThrow();
    expect(server.requests).toHaveLength(0);
    await bsb.db.customers.list().orThrow();
    expect(server.requests.map((request) => request.path)).toEqual([
      "/rest/v1/customers",
    ]);

    const { spec } = betterSupabase;

    const local = await bsb.db
      .$many([spec.tags.count(), spec.tags.list({ select: ["name"] })])
      .orThrow();

    expect(local).toEqual([1, [{ name: "local" }]]);
    await bsb.db.$many([spec.tags.count(), spec.customers.count()]).orThrow();
    expect(server.requests).toHaveLength(2);
  });

  it("runs db on the local database and what SQLite can't on the server", async () => {
    const { bsb, server, statements } = setup();

    await bsb.db.tags.create({ organizationId: ORG, name: "local" }).orThrow();
    const tags = await bsb.db.tags.list({ select: ["name"] }).orThrow();
    expect(tags).toEqual([{ name: "local" }]);
    expect(server.requests).toEqual([]);
    expect(statements.length).toBeGreaterThan(0);

    await bsb.db.customers
      .list({ where: { name: { search: "acme" } } })
      .orThrow();
    expect(server.requests).toHaveLength(1);
  });

  it("keeps every call local with fallback false", async () => {
    const { bsb, server } = setup({ fallback: false });

    const result = await bsb.db.customers.list({
      where: { name: { search: "acme" } },
    });

    expect(result.error).toMatchObject({ kind: "unsupported" });
    expect(server.requests).toEqual([]);
  });

  it("reads a followed source again when PowerSync reports its table", async () => {
    const { bsb, engine, db } = setup();

    const target = dataTarget(
      { db: bsb.db, engine },
      "tags",
      (local: typeof bsb.db) => local.tags,
    );

    const list = createDataList(target, { select: ["name"] });
    const stop = list.subscribe(() => undefined);
    await tick();
    expect(list.getSnapshot().data).toEqual([]);

    await db.execute(
      `insert into "tags" ("id", "organization_id", "name") values (?, ?, ?)`,
      ["t-sync", ORG, "synced"],
    );
    await tick();
    expect(list.getSnapshot().data).toEqual([{ name: "synced" }]);
    stop();
  });

  it("reads every followed source again after a reconnect", async () => {
    const { bsb, engine, setStatus, server } = setup();

    const online = {
      connected: true,
      dataFlowStatus: { uploading: false, downloading: false },
    };

    const target = dataTarget(
      { db: bsb.db, engine },
      "customers",
      (local: typeof bsb.db) => local.customers,
    );

    const list = createDataList(target, {
      where: { name: { search: "acme" } },
    });

    const stop = list.subscribe(() => undefined);
    await tick();
    expect(server.requests).toHaveLength(1);
    setStatus(online);
    await tick();
    expect(server.requests).toHaveLength(2);
    setStatus(online);
    await tick();
    expect(server.requests).toHaveLength(2);
    stop();
  });

  it("follows PowerSync's sync status and the connector's conflicts", () => {
    const changes: never[] = [];

    const rejected = {
      current: () => changes,
      subscribe: () => () => undefined,
      dismiss: () => undefined,
    };

    const { engine, setStatus } = setup({ connector: { rejected } });
    const sync = engine.sync!;
    const first = sync.current();

    expect(first).toEqual({
      connected: false,
      connecting: false,
      hasSynced: false,
      uploading: false,
      downloading: false,
      error: undefined,
    });
    expect(sync.current()).toBe(first);
    expect(sync.conflicts).toBe(rejected);

    const failure = new Error("upload failed");
    let calls = 0;

    const stop = sync.subscribe(() => {
      calls += 1;
    });

    setStatus({
      connected: true,
      hasSynced: true,
      dataFlowStatus: {
        uploading: true,
        downloading: false,
        uploadError: failure,
      },
    });

    expect(calls).toBe(1);
    expect(sync.current()).toMatchObject({
      connected: true,
      hasSynced: true,
      uploading: true,
      error: failure,
    });
    stop();
  });

  it("has no sync status for a database without one", () => {
    const { db } = createSqlite(betterSupabase.meta);

    expect(powersyncEngine(db).sync).toBeUndefined();
  });
});
