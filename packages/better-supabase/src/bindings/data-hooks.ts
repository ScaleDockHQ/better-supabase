import type { Controller } from "../blocks/controller.ts";
import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";
import type { BlockTenant } from "../core/tenant-source.ts";
import type { DataEngine, DataKey } from "./data-engine.ts";

import { defineController } from "../blocks/controller.ts";
import { currentTenant } from "../core/tenant-source.ts";
import { dataKeyHash, memoryEngine, unwrap } from "./data-engine.ts";

type Read<A extends readonly unknown[], T> = (
  ...args: A
) => PromiseLike<Result<T>>;

/**
 * What the data hooks read and write: a table repository or a block instance
 * (`db.customers`, `db.tickets`). Each verb is optional; a hook only calls the
 * ones it uses.
 */
export interface DataSource {
  readonly list?: Read<never[], unknown>;
  readonly get?: Read<never[], unknown>;
  readonly create?: Read<never[], unknown>;
  readonly update?: Read<never[], unknown>;
  readonly delete?: Read<never[], unknown>;
}

type DataOf<F> = F extends (...args: never[]) => PromiseLike<infer R>
  ? R extends { readonly ok: true; readonly data: infer D }
    ? D
    : never
  : never;

type FirstArg<F> = F extends (first: infer A, ...rest: never[]) => unknown
  ? A
  : never;

type SecondArg<F> = F extends (
  first: never,
  second: infer A,
  ...rest: never[]
) => unknown
  ? A
  : never;

/** The rows `source.list` resolves to. */
export type DataRows<S extends DataSource> = DataOf<S["list"]>;

/** The row `source.get` resolves to. */
export type DataRow<S extends DataSource> = DataOf<S["get"]>;

/** What `source.list` takes. */
export type DataListArgs<S extends DataSource> = FirstArg<S["list"]>;

/** The id `source.get`, `update` and `delete` take. */
export type DataId<S extends DataSource> = FirstArg<S["get"]>;

/** A data hook's read: the last data stays while it loads again. */
export interface DataState<T> {
  readonly data: T | undefined;
  readonly error: DbError | undefined;
  /** True until the first answer arrives. */
  readonly isPending: boolean;
  readonly status: "idle" | "loading" | "success" | "error";
}

/**
 * The writes a data hook offers. They update the cached lists at once, roll
 * back on an error, resolve to the row and reject with a `DbException`.
 */
export interface DataWrites<S extends DataSource> {
  readonly refetch: () => void;
  readonly create: (
    input: FirstArg<S["create"]>,
  ) => Promise<DataOf<S["create"]>>;
  readonly update: (
    id: FirstArg<S["update"]>,
    patch: SecondArg<S["update"]>,
  ) => Promise<DataOf<S["update"]>>;
  readonly delete: (id: FirstArg<S["delete"]>) => Promise<DataOf<S["delete"]>>;
}

/** Where a data hook reads: the source, its cache key and the engine. */
export interface DataTarget<S extends DataSource> {
  readonly source: S;
  /** `["bsb", <instance or table>, <organization>]`. */
  readonly scope: DataKey;
  readonly engine: DataEngine;
}

/** The client a data hook reads through: `bsb` from `createClient()`. */
export interface DataClient {
  readonly db: object;
  readonly tenant?: BlockTenant | undefined;
  readonly engine?: DataEngine | undefined;
}

const engines = new WeakMap<object, DataEngine>();

/** The engine a client's data hooks share: its own, or one in memory. */
function engineOf(client: {
  readonly engine?: DataEngine | undefined;
}): DataEngine {
  if (client.engine !== undefined) {
    return client.engine;
  }

  let engine = engines.get(client);

  if (engine === undefined) {
    engine = memoryEngine();
    engines.set(client, engine);
  }

  return engine;
}

function verb<S extends DataSource>(
  source: S,
  name: keyof DataSource,
): (...args: unknown[]) => PromiseLike<Result<unknown>> {
  const method = source[name];

  if (typeof method !== "function") {
    throw new TypeError(`better-supabase: this data source has no ${name}()`);
  }

  // SAFETY: `DataSource` verbs take their arguments as the hook passes them.
  return method.bind(source) as (
    ...args: unknown[]
  ) => PromiseLike<Result<unknown>>;
}

function fields(value: unknown): object {
  return typeof value === "object" && value !== null ? value : {};
}

function idOf(row: unknown): unknown {
  return typeof row === "object" && row !== null && "id" in row
    ? row.id
    : undefined;
}

function sameId(a: unknown, b: unknown): boolean {
  return a !== undefined && dataKeyHash([a]) === dataKeyHash([b]);
}

function mapRows(
  data: unknown,
  each: (rows: readonly unknown[]) => readonly unknown[],
): unknown {
  return Array.isArray(data) ? each(data) : data;
}

function writes<S extends DataSource>(
  target: DataTarget<S>,
  refetch: () => void,
): DataWrites<S> {
  const { source, scope, engine } = target;
  const lists = [...scope, "list"];

  const settle = async <T>(
    run: () => PromiseLike<Result<T>>,
    rollback: readonly (() => void)[],
  ): Promise<T> => {
    try {
      return await unwrap(run());
    } catch (error) {
      for (const restore of rollback) {
        restore();
      }

      throw error;
    } finally {
      engine.invalidate(scope);
    }
  };

  return {
    refetch,
    create: (input) => {
      const optimistic = { ...fields(input), id: undefined };

      const rollback = [
        engine.rewrite(lists, (data) =>
          mapRows(data, (rows) => [...rows, optimistic]),
        ),
      ];

      // SAFETY: `create` resolves to the row `DataOf<S["create"]>` names.
      return settle(() => verb(source, "create")(input), rollback) as Promise<
        DataOf<S["create"]>
      >;
    },
    update: (id, patch) => {
      const merge = (row: unknown): unknown =>
        sameId(idOf(row), id) ? { ...fields(row), ...fields(patch) } : row;

      const rollback = [
        engine.rewrite(lists, (data) =>
          mapRows(data, (rows) => rows.map(merge)),
        ),
        engine.rewrite([...scope, "get", id], merge),
      ];

      // SAFETY: `update` resolves to the row `DataOf<S["update"]>` names.
      return settle(
        () => verb(source, "update")(id, patch),
        rollback,
      ) as Promise<DataOf<S["update"]>>;
    },
    delete: (id) => {
      const rollback = [
        engine.rewrite(lists, (data) =>
          mapRows(data, (rows) => rows.filter((row) => !sameId(idOf(row), id))),
        ),
      ];

      // SAFETY: `delete` resolves to what `DataOf<S["delete"]>` names.
      return settle(() => verb(source, "delete")(id), rollback) as Promise<
        DataOf<S["delete"]>
      >;
    },
  };
}

function readController<S extends DataSource, T>(
  target: DataTarget<S>,
  key: DataKey,
  load: () => Promise<unknown>,
): Controller<DataState<T>, DataWrites<S>> {
  const { engine } = target;

  const snapshot = (): DataState<T> => {
    const entry = engine.entry(key);

    return {
      // SAFETY: the engine holds what `load` resolved to, a `T`.
      data: entry.data as T | undefined,
      error: entry.error,
      isPending: entry.data === undefined && entry.status !== "error",
      status: entry.status,
    };
  };

  return defineController(snapshot(), (state) => ({
    actions: writes(target, () => {
      engine.refetch(key);
    }),
    start: () => {
      const update = (): void => {
        state.set(snapshot());
      };

      const stop = engine.watch(key, load, update);
      update();

      return stop;
    },
  }));
}

/** `source.list(args)` through the engine, with the writes. */
export function createDataList<S extends DataSource>(
  target: DataTarget<S>,
  args: DataListArgs<S> | undefined,
): Controller<DataState<DataRows<S>>, DataWrites<S>> {
  const list = verb(target.source, "list");

  return readController(target, [...target.scope, "list", args ?? null], () =>
    unwrap(args === undefined ? list() : list(args)),
  );
}

/** `source.get(id)` through the engine, with the writes. */
export function createDataOne<S extends DataSource>(
  target: DataTarget<S>,
  id: DataId<S>,
): Controller<DataState<DataRow<S>>, DataWrites<S>> {
  const get = verb(target.source, "get");

  return readController(target, [...target.scope, "get", id], () =>
    unwrap(get(id)),
  );
}

/**
 * Where `select(client.db)` reads: one cache scope per source and organization,
 * in the client's engine.
 */
export function dataTarget<D, S extends DataSource>(
  client: DataClient,
  name: string,
  select: (db: D) => S,
): DataTarget<S> {
  return {
    // SAFETY: `D` is the client's `Db` type the generated hooks name.
    source: select(client.db as D),
    scope: ["bsb", name, currentTenant(client.tenant) ?? null],
    engine: engineOf(client),
  };
}

/** A stable string for hook dependencies. */
export function dataArgsKey(value: unknown): string {
  return dataKeyHash([value ?? null]);
}
