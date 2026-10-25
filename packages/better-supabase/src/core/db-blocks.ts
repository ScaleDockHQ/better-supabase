import type { SupabaseClient } from "@supabase/supabase-js";

import type { BucketRegistry } from "./db-buckets.ts";
import type { BetterSupabase } from "./define.ts";
import type { EventHub } from "./events.ts";
import type { Db, RawRpcOptions, RpcOptions } from "./repository-types.ts";
import type { StandardSchemaV1 } from "./standard.ts";

import { dbError } from "./errors.ts";
import { AsyncResult } from "./result.ts";

import { rawError } from "./block-transport.ts";
import { mapDbError } from "./errors.ts";
import { instanceProperty } from "./instance-property.ts";
import { AsyncResult, err, ok, toDbError } from "./result.ts";

/**
 * What `betterSupabase.blocks()` takes: the `BlockSet` that `defineBlocks`
 * returns. The core reads it structurally, so it imports no block code.
 */
export interface DbBlockSource {
  /** The keys in `blocks.generated.ts` of the instances that have a client. */
  readonly instances: readonly string[];
  /**
   * One instance's client over `db`: its calls run through `db`'s executor, act
   * in `db.$context.tenant` and use `db.$storage` when `db` has Storage.
   */
  client(
    db: object,
    key: string,
    options: { readonly events: EventHub; readonly temporal?: typeof Temporal },
  ): unknown;
  /** The API schema the blocks are wrapped in (`sql.api`), which `$api` calls. */
  readonly api?: string | undefined;
  /**
   * What one instance's client serves, for `defineApi`: its methods and the
   * input schemas of its entities. `undefined` when the client can't be built
   * without a database.
   */
  describe?(key: string): BlockInstanceSurface | undefined;
  /**
   * Types only, never set: the clients by property, which `BlockSetClients`
   * reads.
   */
  readonly $clients?: object;
}

/** One block instance's client, as `DbBlockSource.describe` reports it. */
export interface BlockInstanceSurface {
  /** The block's name, such as `comments`. */
  readonly block: string;
  /** The client's async methods: contract verbs and domain verbs. */
  readonly methods: readonly string[];
  /** The methods of each sub-client, such as `chats` on ai-chat. */
  readonly members: Readonly<Record<string, readonly string[]>>;
  /**
   * Standard Schemas (with Standard JSON Schema) of what the client takes, by
   * entity key: `input` for create, `change` for update, `listFilter` for
   * list.
   */
  readonly schemas: Readonly<
    Record<
      string,
      {
        readonly input?: unknown;
        readonly change?: unknown;
        readonly listFilter?: unknown;
      }
    >
  >;
}

/** The clients a `DbBlockSource` puts on every `Db`, by property. */
export type BlockSetClients<S> = S extends { readonly $clients?: infer K }
  ? NonNullable<K>
  : object;

/**
 * What a definition registers beyond its schema: `buckets()` and `blocks()`.
 * The `Db` type reads it for `$buckets` and the block instances.
 */
export interface DbExtras {
  readonly buckets?: BucketRegistry;
  readonly blocks?: object;
}

/** `B` with `key` set to `value`. */
export type WithExtra<B, K extends keyof DbExtras, V> = Omit<
  unknown extends B ? object : B,
  K
> & { readonly [P in K]: V };

/** The buckets in `B`, a definition's `DbExtras`. */
export type BucketsOf<B> = B extends { readonly buckets: infer R }
  ? R
  : unknown;

/** The block clients in `B`, a definition's `DbExtras`. */
export type BlockClientsOf<B> = B extends { readonly blocks: infer K }
  ? K
  : unknown;

/**
 * Each block instance on a `Db`, under its key in camel case (`db.tags`,
 * `db.leadScoring`) unless a table `T` holds that property, and always under
 * `db.$blocks`, plus `$api` for the API schema's other functions.
 */
export type BlocksHelper<K, T extends PropertyKey = never> = unknown extends K
  ? unknown
  : Omit<K, T> & {
      /** Every block instance, including those whose property a table holds. */
      readonly $blocks: K;
      /**
       * Calls `fn` in the API schema the blocks are wrapped in, as the `Db`'s
       * caller, through `$rpc`: the error is a `DbError` in the result, and a
       * `returns` schema validates the value and types it.
       */
      $api<R>(
        fn: string,
        args: Readonly<Record<string, unknown>> | undefined,
        options: ApiOptions & {
          readonly returns: StandardSchemaV1<unknown, R>;
        },
      ): AsyncResult<R>;
      $api(
        fn: string,
        args?: Readonly<Record<string, unknown>>,
        options?: ApiOptions,
      ): AsyncResult<unknown>;
    };

/** Options for `db.$api`: `$rpc`'s, without `schema`. */
export type ApiOptions =
  | Omit<RpcOptions<unknown>, "schema" | "returns">
  | Omit<RawRpcOptions, "schema">;

/**
 * The `Db` a definition connects in the browser: what `bsb.db` holds and what
 * the generated data hooks read (`DbOf<typeof betterSupabase>`).
 */
export type DbOf<T> =
  T extends BetterSupabase<
    infer M,
    infer _D,
    infer F,
    infer E,
    infer _C,
    infer _P,
    infer B
  >
    ? Db<M, F, E, SupabaseClient, B>
    : never;

/**
 * A prototype for every `Db` of a definition, with one getter per block
 * instance (skipping those whose property a table holds) and `$blocks` with all
 * of them. Each getter builds the instance's client for the `Db` it is read on,
 * once, so `$with` and every request get their own.
 */
export function blocksPrototype(
  source: DbBlockSource,
  parent: object,
  tables: readonly string[],
  events: EventHub,
  temporal?: typeof Temporal,
): object {
  // SAFETY: Object.create returns a plain object whose prototype is `parent`.
  const prototype = Object.create(parent) as object;
  const built = new WeakMap<object, Map<string, unknown>>();

  const clientOf = (db: object, key: string): unknown => {
    let clients = built.get(db);

    if (clients === undefined) {
      clients = new Map();
      built.set(db, clients);
    }

    if (!clients.has(key)) {
      clients.set(
        key,
        source.client(db, key, {
          events,
          ...(temporal === undefined ? {} : { temporal }),
        }),
      );
    }

    return clients.get(key);
  };

  const views = new WeakMap<object, object>();

  for (const key of source.instances) {
    const property = instanceProperty(key);

    if (tables.includes(property)) {
      continue;
    }

    Object.defineProperty(prototype, property, {
      get(this: object) {
        return clientOf(this, key);
      },
      configurable: true,
      enumerable: false,
    });
  }

  Object.defineProperty(prototype, "$blocks", {
    get(this: object) {
      let view = views.get(this);

      if (view === undefined) {
        view = Object.defineProperties(
          {},
          Object.fromEntries(
            source.instances.map((key) => [
              instanceProperty(key),
              { get: () => clientOf(this, key), enumerable: true },
            ]),
          ),
        );
        views.set(this, view);
      }

      return view;
    },
    configurable: true,
    enumerable: false,
  });

  Object.defineProperty(prototype, "$api", {
    value(
      this: { $rpc(...rest: unknown[]): AsyncResult<unknown> },
      fn: string,
      args: Readonly<Record<string, unknown>> = {},
      options: object = {},
    ): AsyncResult<unknown> {
      if (source.api === undefined) {
        return AsyncResult.err(
          dbError(
            "unsupported",
            "No block has an API schema (`sql.api`) for $api to call",
          ),
        );
      }

      return this.$rpc(fn, args, { ...options, schema: source.api });
    },
    configurable: true,
    enumerable: false,
    writable: false,
  });

  Object.defineProperty(prototype, "$apiResult", {
    value(this: object, fn: string, args: Readonly<Record<string, unknown>>) {
      return AsyncResult.from(async () => {
        try {
          return ok(await source.call(this, fn, args));
        } catch (cause) {
          const raw = rawError(cause);

          return err(raw === undefined ? toDbError(cause) : mapDbError(raw));
        }
      });
    },
    configurable: true,
    enumerable: false,
    writable: false,
  });

  return prototype;
}
