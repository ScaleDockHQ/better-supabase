import type { Executor } from "../../core/executor.ts";
import type { AnyPlugin, HookArgs, RequestContext } from "../../core/plugin.ts";
import type { Operation } from "../../ir/types.ts";

import { dbError } from "../../core/errors.ts";
import { ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { actor } from "../../plugins/actor/index.ts";
import { softDelete } from "../../plugins/soft-delete/index.ts";
import { tenant } from "../../plugins/tenant/index.ts";
import { timestamps } from "../../plugins/timestamps/index.ts";
import {
  Violation,
  conform,
  expect,
  frozenCopy,
  same,
  type ConformanceReport,
} from "../conformance.ts";
import {
  captureOp,
  hasName,
  recorder,
  tableKey,
  type AnyDb,
  type AnySupabase,
} from "./executor.ts";

export interface TestPluginOptions {
  /** The definition without this plugin. */
  readonly betterSupabase: AnySupabase;
  /** Table to exercise. Defaults to the first table. */
  readonly table?: string;
  /** Context the plugin needs, such as `{ tenant }` for `tenant()`. */
  readonly context?: RequestContext;
  /** Row for `create`, to exercise `beforeMutation`. */
  readonly create?: Readonly<Record<string, unknown>>;
}

/**
 * Proves a `Plugin` targets API v1, installs cleanly on its own and next to
 * the first-party plugins in either order, adds repository methods without
 * replacing base ones, keeps `context`, `transformQuery` and
 * `beforeMutation` pure and deterministic, and keeps executors'
 * results intact when it wraps them.
 */
export function testPlugin(
  plugin: AnyPlugin,
  options: TestPluginOptions,
): Promise<ConformanceReport> {
  const { betterSupabase } = options;
  const table = tableKey(betterSupabase, options.table);
  const context = options.context ?? {};
  const hook = (op: Operation): HookArgs => ({
    table: op.table,
    schema: betterSupabase.meta,
    context,
    options: {},
    now: () => temporal().Instant.fromEpochMilliseconds(0),
  });
  const create = options.create;
  return conform(`Plugin "${plugin.name}"`, [
    hasName(plugin),
    [
      "targets plugin API v1",
      () => {
        expect(
          // oxlint-disable-next-line typescript/no-unnecessary-condition -- the kit checks plugins written in JavaScript too.
          plugin.apiVersion === 1,
          `apiVersion is ${String(plugin.apiVersion)}`,
        );
      },
    ],
    [
      "installs and builds repositories",
      () => {
        // SAFETY: the kit runs against any schema, so it indexes repositories
        // by table name.
        // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the kit runs against any schema, so repositories are indexed by name.
        const db = betterSupabase
          .use(plugin)
          .connect(recorder([]), context) as unknown as AnyDb;
        for (const key of Object.keys(betterSupabase.meta.tables))
          expect(db[key], `db.${key} is missing`);
      },
    ],
    [
      "declares a known hook order",
      () => {
        const enforce: unknown = plugin.enforce;
        expect(
          enforce === undefined ||
            enforce === "first" ||
            enforce === "pre" ||
            enforce === "post",
          `enforce is ${String(enforce)}; use "first", "pre", "post" or leave it out`,
        );
      },
    ],
    [
      "installs next to the first-party plugins in either order",
      () => {
        const others = [timestamps(), softDelete(), tenant(), actor()].filter(
          (other) => other.name !== plugin.name,
        );
        let before: AnySupabase = betterSupabase;
        for (const other of others) before = before.use(other);
        let after: AnySupabase = betterSupabase.use(plugin);
        for (const other of others) after = after.use(other);
        for (const installed of [before.use(plugin), after]) {
          // SAFETY: the kit runs against any schema, so it indexes repositories
          // by table name.
          // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the kit runs against any schema, so repositories are indexed by name.
          const db = installed.connect(
            recorder([]),
            context,
          ) as unknown as AnyDb;
          for (const key of Object.keys(betterSupabase.meta.tables))
            expect(db[key], `db.${key} is missing`);
        }
      },
    ],
    plugin.repository && [
      "repository adds functions and keeps the base methods",
      () => {
        // SAFETY: the kit runs against any schema, so it indexes repositories
        // by table name.
        // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the kit runs against any schema, so repositories are indexed by name.
        const db = betterSupabase.connect(
          recorder([]),
          context,
        ) as unknown as AnyDb;
        for (const [key, table] of Object.entries(betterSupabase.meta.tables)) {
          const base = db[key]!;
          const added = plugin.repository!({ table, base });
          if (added === undefined) continue;
          for (const [name, method] of Object.entries(added)) {
            expect(
              typeof method === "function",
              `${key}.${name} is not a function`,
            );
            expect(!(name in base), `${key}.${name} replaces a base method`);
          }
        }
      },
    ],
    plugin.transformQuery && [
      "transformQuery is pure and deterministic",
      async () => {
        const op = await captureOp(betterSupabase, (db) =>
          db[table]!["findMany"]!({ limit: 1 }),
        );
        const first = plugin.transformQuery!(frozenCopy(op), hook(op));
        const second = plugin.transformQuery!(frozenCopy(op), hook(op));
        expect(
          // oxlint-disable-next-line typescript/no-unnecessary-condition -- the kit checks plugins written in JavaScript too.
          typeof first === "object" && first !== null && first.kind === op.kind,
          "must return an operation of the same kind",
        );
        expect(same(first, second), "two calls with the same input differ");
      },
    ],
    plugin.beforeMutation &&
      create && [
        "beforeMutation is pure and deterministic",
        async () => {
          const op = await captureOp(betterSupabase, (db) =>
            db[table]!["create"]!(create),
          );
          if (op.kind === "select")
            throw new Violation("create did not produce a mutation");
          const first = await plugin.beforeMutation!(frozenCopy(op), hook(op));
          const second = await plugin.beforeMutation!(frozenCopy(op), hook(op));
          expect(
            first.kind === op.kind,
            "must return a mutation of the same kind",
          );
          expect(same(first, second), "two calls with the same input differ");
        },
      ],
    plugin.afterMutation &&
      create && [
        "afterMutation cannot change the result",
        async () => {
          const row = { marker: "conformance", nested: { kept: true } };
          const executor: Executor = {
            name: "rows",
            execute: () =>
              Promise.resolve(ok({ rows: [structuredClone(row)], count: 1 })),
          };
          // SAFETY: the kit runs against any schema, so it indexes repositories
          // by table name.
          // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the kit runs against any schema, so repositories are indexed by name.
          const db = betterSupabase
            .use(plugin)
            .connect(executor, context) as unknown as AnyDb;
          const result = await db[table]!["create"]!(create);
          expect(result.ok, "create failed");
          expect(
            same(result.data, row),
            "afterMutation changed the returned row",
          );
        },
      ],
    plugin.wrapExecutor && [
      "wrapExecutor keeps results intact",
      async () => {
        const op = await captureOp(betterSupabase, (db) =>
          db[table]!["findMany"]!({ limit: 1 }),
        );
        const data = { rows: [{ marker: "conformance" }], count: 1 };
        const wrapped = plugin.wrapExecutor!({
          name: "inner",
          execute: () => Promise.resolve(ok(data)),
        });
        expect(
          typeof wrapped.name === "string",
          "the wrapped executor needs a name",
        );
        const result = await wrapped.execute(op, { errorMappers: [] });
        expect(
          result.ok && same(result.data, data),
          "the wrapped executor changed the result",
        );
      },
    ],
    plugin.context && [
      "context is pure and deterministic",
      () => {
        const args = { schema: betterSupabase.meta };
        const first = plugin.context!(frozenCopy(context), args);
        const second = plugin.context!(frozenCopy(context), args);
        expect(
          // oxlint-disable-next-line typescript/no-unnecessary-condition -- the kit checks plugins written in JavaScript too.
          typeof first === "object" && first !== null,
          "must return a context object",
        );
        expect(same(first, second), "two calls with the same input differ");
      },
    ],
    plugin.mapError && [
      "mapError returns a DbError or undefined",
      () => {
        const fallback = dbError("unexpected", "internal error");
        const mapped = plugin.mapError!(
          { code: "XX000", message: "internal error" },
          fallback,
        );
        expect(
          mapped === undefined ||
            (typeof mapped === "object" && typeof mapped.kind === "string"),
          "must return a DbError or undefined",
        );
      },
    ],
  ]);
}
