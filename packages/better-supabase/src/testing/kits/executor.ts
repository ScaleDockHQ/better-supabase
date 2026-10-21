import type { BetterSupabase } from "../../core/define.ts";
import type { ExecuteContext, Executor } from "../../core/executor.ts";
import type { Operation } from "../../ir/types.ts";
import type { Check, ConformanceReport } from "../conformance.ts";

import { isList } from "../../core/guards.ts";
import { ok } from "../../core/result.ts";
import { conform, expect, same } from "../conformance.ts";

// oxlint-disable-next-line typescript/no-explicit-any -- the kit takes any configured client, and its type parameters are invariant
export type AnySupabase = BetterSupabase<any, any, any, any>;

export type AnyDb = Record<
  string,
  Record<
    string,
    (
      ...args: unknown[]
    ) => PromiseLike<{ ok: boolean; data?: unknown; error?: unknown }>
  >
>;

export const recorder = (ops: Operation[]): Executor => ({
  name: "recorder",
  execute: (op) => {
    ops.push(op);

    return Promise.resolve(ok({ rows: [], count: 0 }));
  },
});

/**
 * The operation `run` sends to the executor, built by `betterSupabase` without
 * touching a database.
 */
export async function captureOp(
  betterSupabase: AnySupabase,
  run: (db: AnyDb) => PromiseLike<unknown>,
): Promise<Operation> {
  const ops: Operation[] = [];
  await run(betterSupabase.connect(recorder(ops)));
  const [op] = ops;

  if (!op) {
    throw new Error("the repository call did not reach the executor");
  }

  return op;
}

export function tableKey(
  betterSupabase: AnySupabase,
  table: string | undefined,
): string {
  const key = table ?? Object.keys(betterSupabase.meta.tables)[0];

  if (!key || !(key in betterSupabase.meta.tables)) {
    throw new TypeError(`better-supabase: unknown table "${String(key)}"`);
  }

  return key;
}

export const hasName = (subject: { readonly name?: unknown }): Check => [
  "has a name",
  () => {
    expect(
      typeof subject.name === "string" && subject.name.length > 0,
      "name must be a non-empty string",
    );
  },
];

export interface TestExecutorOptions {
  /**
   * A definition whose schema matches the executor's database. Install no
   * plugins.
   */
  readonly betterSupabase: AnySupabase;
  /**
   * App key of a table with rows the executor can read. Defaults to the first
   * table.
   */
  readonly table?: string;
  /**
   * A row to insert and delete again, to check writes. Skips write checks when
   * omitted.
   */
  readonly create?: Readonly<Record<string, unknown>>;
}

/**
 * Proves an `Executor` meets the contract: rows keyed by the selection's
 * aliases, counts, `aborted` errors, failures returned as `Result`s rather than
 * thrown, and (with `create`) a write round trip and a `deleteMany` that
 * `maxAffected` refuses without deleting anything.
 *
 * ```ts
 * it("conforms", () =>
 *   testExecutor(myExecutor, {
 *     betterSupabase,
 *     table: "tags",
 *     create: { name: "x" },
 *   }));
 * ```
 */
export function testExecutor(
  executor: Executor,
  options: TestExecutorOptions,
): Promise<ConformanceReport> {
  const { betterSupabase } = options;
  const table = tableKey(betterSupabase, options.table);
  const context: ExecuteContext = { errorMappers: [] };

  const read = (): Promise<Operation> =>
    captureOp(betterSupabase, (db) => db[table]!["findMany"]!({ limit: 2 }));

  const create = options.create;

  return conform(`Executor "${executor.name}"`, [
    hasName(executor),
    [
      "reads rows keyed by the selection aliases",
      async () => {
        const op = await read();
        const result = await executor.execute(op, context);
        expect(
          result.ok,
          `select failed: ${result.ok ? "" : result.error.message}`,
        );
        expect(isList(result.data.rows), "rows must be an array");
        expect(
          result.data.rows.length <= 2,
          `limit 2 returned ${result.data.rows.length} rows`,
        );
        expect(
          result.data.count === null || typeof result.data.count === "number",
          "count must be a number or null",
        );

        if (op.kind !== "select") {
          return;
        }

        const aliases = new Set(
          op.selection.columns.map((column) => column.alias),
        );

        for (const row of result.data.rows) {
          const extra = Object.keys(row).filter((key) => !aliases.has(key));
          expect(
            extra.length === 0,
            `rows must use selection aliases; got ${extra.join(", ")}`,
          );
        }
      },
    ],
    [
      "counts rows",
      async () => {
        const op = await captureOp(betterSupabase, (db) =>
          db[table]!["count"]!(),
        );

        const result = await executor.execute(op, context);
        expect(
          result.ok,
          `count failed: ${result.ok ? "" : result.error.message}`,
        );
        expect(
          typeof result.data.count === "number" && result.data.count >= 0,
          "count must be a number",
        );
      },
    ],
    [
      "returns an aborted error for an aborted signal",
      async () => {
        const controller = new AbortController();
        controller.abort();

        const result = await executor.execute(await read(), {
          ...context,
          signal: controller.signal,
        });

        expect(!result.ok, "an aborted request must fail");
        expect(
          result.error.kind === "aborted",
          `expected kind "aborted", got "${result.error.kind}"`,
        );
      },
    ],
    [
      "returns failures as results instead of throwing",
      async () => {
        const op = await read();

        // SAFETY: only the table name changes, so the copy is still an Operation.
        const missing = {
          ...op,
          table: { ...op.table, name: "__better_supabase_missing__" },
        } as Operation;

        const result = await executor.execute(missing, context);
        expect(!result.ok, "a missing table must fail");
        expect(
          typeof result.error.kind === "string" &&
            typeof result.error.message === "string",
          "errors must be DbErrors",
        );
      },
    ],
    executor.rpc && [
      "returns rpc failures as results",
      async () => {
        const result = await executor.rpc!(
          "__better_supabase_missing__",
          {},
          { ...context, schema: "public" },
        );

        expect(!result.ok, "calling a missing function must fail");
      },
    ],
    executor.functionSources && [
      "reads from SelectOp.source instead of the table",
      async () => {
        const op = await read();

        if (op.kind !== "select") {
          return;
        }

        const result = await executor.execute(
          {
            ...op,
            source: {
              schema: op.table.schema,
              name: "__better_supabase_missing__",
              args: {},
            },
          },
          context,
        );

        expect(
          !result.ok,
          "a missing source function must fail; reading the table ignores source",
        );
      },
    ],
    executor.batch && [
      "batch returns one result per operation, in order",
      async () => {
        const rows = await read();

        const count = await captureOp(betterSupabase, (db) =>
          db[table]!["count"]!(),
        );

        // SAFETY: only the table name changes, so the copy is still an Operation.
        const missing = {
          ...rows,
          table: { ...rows.table, name: "__better_supabase_missing__" },
        } as Operation;

        const results = await executor.batch!([rows, count, missing], context);
        expect(
          results.length === 3,
          `expected 3 results, got ${results.length}`,
        );
        const [first, second, third] = results;
        expect(
          first?.ok === true && Array.isArray(first.data.rows),
          "the first operation must return rows",
        );
        expect(
          second?.ok === true && typeof second.data.count === "number",
          "the second operation must return a count",
        );
        expect(
          third?.ok === false,
          "a failing operation must fail on its own, as a result",
        );
      },
    ],
    create && [
      "round-trips a write",
      async () => {
        // SAFETY: the kit runs against any schema, so it indexes repositories
        // by table name.
        const db =
          // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the kit runs against any schema, so repositories are indexed by name.
          betterSupabase.connect(executor) as unknown as AnyDb;

        const repository = db[table]!;
        const created = await repository["create"]!(create);
        expect(created.ok, `create failed: ${JSON.stringify(created.error)}`);
        // SAFETY: the ok check above means create returned the inserted row.
        const row = created.data as Record<string, unknown>;

        for (const [key, value] of Object.entries(create)) {
          expect(
            same(row[key], value),
            `created row has ${key} = ${JSON.stringify(row[key])}`,
          );
        }

        const [primary] = betterSupabase.meta.tables[table]!.primaryKey;
        expect(primary, "write checks need a table with a primary key");
        const removed = await repository["delete"]!(row[primary]);
        expect(removed.ok, `delete failed: ${JSON.stringify(removed.error)}`);

        const again = await repository["findFirst"]!({
          where: { [primary]: row[primary] },
        });

        expect(
          again.ok && again.data === null,
          "the deleted row is still readable",
        );
      },
    ],
    create && [
      "refuses a write past maxAffected and writes nothing",
      async () => {
        // SAFETY: the kit runs against any schema, so it indexes repositories
        // by table name.
        const db =
          // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the kit runs against any schema, so repositories are indexed by name.
          betterSupabase.connect(executor) as unknown as AnyDb;

        const repository = db[table]!;
        const [primary] = betterSupabase.meta.tables[table]!.primaryKey;
        expect(primary, "write checks need a table with a primary key");
        const created = await repository["create"]!(create);
        expect(created.ok, `create failed: ${JSON.stringify(created.error)}`);
        // SAFETY: the ok check above means create returned the inserted row.
        const id = (created.data as Record<string, unknown>)[primary];

        try {
          const refused = await repository["deleteMany"]!({
            where: { [primary]: id },
            maxAffected: 0,
          });

          expect(!refused.ok, "deleteMany past maxAffected must fail");
          // SAFETY: the ok check above means the result carries an error.
          const kind = (refused.error as { kind?: unknown } | undefined)?.kind;
          expect(
            kind === "max_affected",
            `expected kind "max_affected", got "${String(kind)}"`,
          );

          const kept = await repository["findFirst"]!({
            where: { [primary]: id },
          });

          expect(
            kept.ok && kept.data !== null,
            "a refused deleteMany must not delete the row",
          );

          const allowed = await repository["deleteMany"]!({
            where: { [primary]: id },
            maxAffected: 1,
          });

          expect(
            allowed.ok,
            `deleteMany within maxAffected failed: ${JSON.stringify(allowed.error)}`,
          );
        } finally {
          await repository["delete"]!(id);
        }
      },
    ],
  ]);
}
