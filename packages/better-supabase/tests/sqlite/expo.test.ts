import type { DatabaseSync, SQLInputValue } from "node:sqlite";

import { describe, expect, it, vi } from "vitest";

import type { Executor } from "../../src/core/executor.ts";
import type {
  DatabaseChangeEventLike,
  ExpoSqliteContextLike,
  ExpoSqliteDatabaseLike,
} from "../../src/sqlite/index.ts";

import { createDataList, dataTarget } from "../../src/bindings/data-hooks.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { expoSqliteDatabase, sqliteEngine } from "../../src/sqlite/index.ts";
import { testExecutor } from "../../src/testing/kits/executor.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createSqlite } from "../fixtures/sqlite.ts";

const betterSupabase = defineSupabase(schema);
const ORG = "00000000-0000-4000-8000-000000000001";
const WRITES = /^\s*(?:insert into|update|delete from)\s+"([^"]+)"/i;

/** An expo-sqlite `SQLiteDatabase` over node:sqlite, with change events. */
function fakeExpo(
  sqlite: DatabaseSync,
  { exclusive = true }: { exclusive?: boolean } = {},
) {
  const listeners = new Set<(event: DatabaseChangeEventLike) => void>();

  const context: ExpoSqliteContextLike = {
    getAllAsync<T>(source: string, params: unknown[]): Promise<T[]> {
      try {
        return Promise.resolve(
          sqlite.prepare(source).all(...(params as SQLInputValue[])) as T[],
        );
      } catch (cause) {
        return Promise.reject(cause);
      }
    },
    runAsync(source: string, params: unknown[]): Promise<unknown> {
      try {
        const result = sqlite
          .prepare(source)
          .run(...(params as SQLInputValue[]));

        const table = WRITES.exec(source)?.[1];

        if (table) {
          for (const listener of listeners) {
            listener({ tableName: table, databaseFilePath: "/app.db" });
          }
        }

        return Promise.resolve(result);
      } catch (cause) {
        return Promise.reject(cause);
      }
    },
  };

  const transaction = async (task: () => Promise<void>): Promise<void> => {
    sqlite.exec("begin");

    try {
      await task();
      sqlite.exec("commit");
    } catch (cause) {
      sqlite.exec("rollback");
      throw cause;
    }
  };

  const db: ExpoSqliteDatabaseLike = {
    ...context,
    databasePath: "/app.db",
    withTransactionAsync: transaction,
    ...(exclusive
      ? {
          withExclusiveTransactionAsync: (
            task: (txn: ExpoSqliteContextLike) => Promise<void>,
          ) => transaction(() => task(context)),
        }
      : {}),
  };

  const addDatabaseChangeListener = (
    listener: (event: DatabaseChangeEventLike) => void,
  ) => {
    listeners.add(listener);

    return {
      remove: () => {
        listeners.delete(listener);
      },
    };
  };

  return { db, addDatabaseChangeListener, listeners };
}

const server: Executor = {
  name: "server",
  execute: () => {
    throw new Error("the server is not used here");
  },
};

function setup(options: { exclusive?: boolean } = {}) {
  const { sqlite } = createSqlite(betterSupabase.meta);
  const expo = fakeExpo(sqlite, options);

  const engine = sqliteEngine(
    expoSqliteDatabase(expo.db, {
      addDatabaseChangeListener: expo.addDatabaseChangeListener,
    }),
    { fallback: false },
  );

  const executor = engine.connect!(server);

  return {
    ...expo,
    sqlite,
    engine,
    executor,
    client: betterSupabase.connect(executor),
  };
}

describe("sqliteEngine on expo-sqlite", () => {
  it("conforms to the executor contract", () => {
    const { executor } = setup();
    expect(executor.name).toBe("sqlite");

    return testExecutor(executor, {
      betterSupabase,
      table: "tags",
      create: { organizationId: ORG, name: "conformance" },
    });
  });

  it("writes and reads rows in the PostgREST shape on web transactions", async () => {
    const { client } = setup({ exclusive: false });

    const customer = await client.customers
      .create({ organizationId: ORG, name: "Acme", metadata: { tier: "pro" } })
      .orThrow();

    expect(customer.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(customer.metadata).toEqual({ tier: "pro" });

    const found = await client.customers
      .list({ where: { name: "Acme" }, select: ["id", "name"] })
      .orThrow();

    expect(found).toEqual([{ id: customer.id, name: "Acme" }]);
  });

  it("makes a UUID in SQLite without crypto.randomUUID", async () => {
    vi.stubGlobal("crypto", undefined);

    try {
      const { client } = setup();

      const tag = await client.tags
        .create({ organizationId: ORG, name: "no-crypto" })
        .orThrow();

      expect(tag.id).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      );
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it("rolls a failed write back", async () => {
    const { client } = setup();
    await client.tags.create({ organizationId: ORG, name: "dup" }).orThrow();

    const again = await client.tags.create({
      organizationId: ORG,
      name: "dup",
    });

    expect(again).toMatchObject({ ok: false, error: { kind: "conflict" } });
  });
});

describe("expoSqliteDatabase", () => {
  it("reads a followed source again after a change to its table, batched", async () => {
    vi.useFakeTimers();

    try {
      const { client, engine, listeners } = setup();

      const target = dataTarget(
        { db: client, engine },
        "tags",
        (db: typeof client) => db.tags,
      );

      const list = createDataList(target, { where: { organizationId: ORG } });
      const lengths: number[] = [];

      const stop = list.subscribe(() => {
        const { data } = list.getSnapshot();

        if (data !== undefined) {
          lengths.push(data.length);
        }
      });

      await vi.advanceTimersByTimeAsync(0);
      expect(list.getSnapshot().data).toEqual([]);
      await client.tags.create({ organizationId: ORG, name: "a" }).orThrow();
      await client.tags.create({ organizationId: ORG, name: "b" }).orThrow();
      await client.customers
        .create({ organizationId: ORG, name: "ignored" })
        .orThrow();
      await vi.advanceTimersByTimeAsync(30);
      expect(list.getSnapshot().data).toHaveLength(2);
      expect(lengths.at(-1)).toBe(2);
      stop();
      expect(listeners.size).toBe(0);
    } finally {
      vi.useRealTimers();
    }
  });

  it("ignores changes to another database file", () => {
    const { db, addDatabaseChangeListener, listeners } = setup();
    const database = expoSqliteDatabase(db, { addDatabaseChangeListener });
    const onChange = vi.fn();
    vi.useFakeTimers();

    try {
      const controller = new AbortController();
      database.onChange!({ onChange }, { signal: controller.signal });

      for (const listener of listeners) {
        listener({ tableName: "tags", databaseFilePath: "/other.db" });
      }

      vi.advanceTimersByTime(50);
      expect(onChange).not.toHaveBeenCalled();
      controller.abort();
      expect(listeners.size).toBe(0);
    } finally {
      vi.useRealTimers();
    }
  });

  it("has no onChange without a change listener", () => {
    const { db } = setup();
    expect("onChange" in expoSqliteDatabase(db)).toBe(false);
  });
});
