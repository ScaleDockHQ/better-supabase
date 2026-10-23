import type { SQLInputValue } from "node:sqlite";

import { describe, expect, it } from "vitest";

import type { Executor } from "../../src/core/executor.ts";

import { createDataList, dataTarget } from "../../src/bindings/data-hooks.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { liteDatabase, sqliteEngine } from "../../src/sqlite/index.ts";
import { testExecutor } from "../../src/testing/kits/executor.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createSqlite } from "../fixtures/sqlite.ts";

const betterSupabase = defineSupabase(schema);
const ORG = "00000000-0000-4000-8000-000000000001";

const server: Executor = {
  name: "server",
  execute: () => {
    throw new Error("the server is not used here");
  },
};

const tick = (): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

/** A Supabase Lite connection over node:sqlite: `exec` returns `{ rows }`. */
function liteConnection() {
  const { sqlite } = createSqlite(betterSupabase.meta);
  const statements: string[] = [];

  const connection = {
    exec: <T>(query: string, ...parameters: readonly unknown[]): Promise<T> => {
      statements.push(query);

      try {
        const statement = sqlite.prepare(query);
        // SAFETY: the executor binds only SQLite values.
        const values = parameters as SQLInputValue[];

        // SAFETY: Lite resolves reads to `{ rows }` and the rest to nothing.
        return Promise.resolve(
          (statement.columns().length > 0
            ? { rows: statement.all(...values) }
            : (statement.run(...values), undefined)) as T,
        );
      } catch (cause) {
        return Promise.reject(cause);
      }
    },
  };

  return { connection, statements };
}

function setup() {
  const lite = liteConnection();

  const engine = sqliteEngine(liteDatabase(lite.connection), {
    fallback: false,
  });

  const executor = engine.connect!(server);

  return { ...lite, engine, executor, db: betterSupabase.connect(executor) };
}

describe("sqliteEngine on Supabase Lite", () => {
  it("conforms to the executor contract", () => {
    const { executor } = setup();

    return testExecutor(executor, {
      betterSupabase,
      table: "tags",
      create: { organizationId: ORG, name: "conformance" },
    });
  });

  it("runs writes in a transaction and rolls a failed one back", async () => {
    const { db, statements } = setup();
    await db.tags.create({ organizationId: ORG, name: "dup" }).orThrow();
    expect(statements).toContain("begin");
    expect(statements).toContain("commit");

    const again = await db.tags.create({ organizationId: ORG, name: "dup" });
    expect(again).toMatchObject({ ok: false, error: { kind: "conflict" } });
    expect(statements).toContain("rollback");
    expect(await db.tags.count().orThrow()).toBe(1);
  });

  it("reads a followed source again after db writes its table", async () => {
    const { db, engine } = setup();

    const target = dataTarget(
      { db, engine },
      "tags",
      (local: typeof db) => local.tags,
    );

    const list = createDataList(target, { select: ["name"] });
    const stop = list.subscribe(() => undefined);
    await tick();
    expect(list.getSnapshot().data).toEqual([]);

    await db.tags.create({ organizationId: ORG, name: "a" }).orThrow();
    await tick();
    expect(list.getSnapshot().data).toEqual([{ name: "a" }]);

    await db.customers.create({ organizationId: ORG, name: "A" }).orThrow();
    await db.tags.list().orThrow();
    await tick();
    expect(list.getSnapshot().data).toEqual([{ name: "a" }]);
    stop();
  });
});
