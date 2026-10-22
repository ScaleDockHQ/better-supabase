import type { QueryClient, SkipToken } from "@tanstack/query-core";

import type { EventHub } from "../core/events.ts";
import type { Result } from "../core/result.ts";
import type {
  MutationOptionsOf,
  QueriesOptions,
  QueryOptionsOf,
} from "./queries.ts";

import { DbException } from "../core/errors.ts";
import { invalidateTables } from "./invalidate.ts";
import { keyPart } from "./queries.ts";

/** The first key part of every query, a table's or a block instance's. */
const BLOCK_KEY = "bsb";

/**
 * Method name prefixes that read: these become query options, every other
 * method becomes mutation options.
 */
export const BLOCK_READ_PREFIXES = [
  "can",
  "count",
  "find",
  "get",
  "has",
  "is",
  "list",
  "load",
  "preview",
  "read",
  "resolve",
  "search",
  "tree",
] as const;

type ReadPrefix = (typeof BLOCK_READ_PREFIXES)[number];

type AnyMethod = (...args: never[]) => PromiseLike<Result<unknown>>;

type DataOf<F> = F extends (...args: never[]) => PromiseLike<infer R>
  ? R extends { readonly ok: true; readonly data: infer D }
    ? D
    : never
  : never;

/**
 * What a block mutation takes: the one argument of a method with at most one
 * parameter, else the arguments as a tuple.
 */
export type BlockVariablesOf<F extends AnyMethod> =
  Parameters<F>["length"] extends 0 | 1 ? Parameters<F>[0] : Parameters<F>;

type MethodKeys<C> = {
  readonly [K in keyof C]: C[K] extends AnyMethod ? K : never;
}[keyof C] &
  string;

/** The query or mutation options of one block method. */
export type BlockMethodQuery<K extends string, F extends AnyMethod> = K extends
  | ReadPrefix
  | `${ReadPrefix}${Capitalize<string>}`
  ? (...args: Parameters<F> | [SkipToken]) => QueryOptionsOf<DataOf<F>>
  : () => MutationOptionsOf<BlockVariablesOf<F>, DataOf<F>>;

/** Query and mutation options for one block client, by method. */
export type BlockClientQueries<C> = {
  readonly [K in MethodKeys<C>]: C[K] extends AnyMethod
    ? BlockMethodQuery<K, C[K]>
    : never;
} & {
  /** Prefix of every key for this block's queries. */
  readonly $key: readonly [typeof BLOCK_KEY, string];
};

/** `blockQueries(clients)`: query and mutation options for each block. */
export type BlockQueries<C> = {
  readonly [K in keyof C & string]: BlockClientQueries<C[K]>;
};

/** The block clients `createBlocks` built, by key. */
export type BlockClients = Readonly<Record<string, object>>;

function isSkip(value: unknown): value is SkipToken {
  return typeof value === "symbol";
}

function isReadName(name: string): boolean {
  return BLOCK_READ_PREFIXES.some(
    (prefix) =>
      name.startsWith(prefix) &&
      (name.length === prefix.length ||
        name.charAt(prefix.length) ===
          name.charAt(prefix.length).toUpperCase()),
  );
}

async function unwrap(result: PromiseLike<Result<unknown>>): Promise<unknown> {
  const settled = await result;

  if (!settled.ok) {
    throw new DbException(settled.error);
  }

  return settled.data;
}

function memberOf(client: object, name: string): unknown {
  // SAFETY: a read of one property name the client or its prototypes declare.
  return (client as Readonly<Record<string, unknown>>)[name];
}

function methodOf(
  client: object,
  name: string,
): ((...args: unknown[]) => PromiseLike<Result<unknown>>) | undefined {
  const value = memberOf(client, name);

  // SAFETY: block client methods return an `AsyncResult`, which is a
  // `PromiseLike<Result>`; `unwrap` reads only `ok`, `data` and `error`.
  return typeof value === "function"
    ? (value.bind(client) as (
        ...args: unknown[]
      ) => PromiseLike<Result<unknown>>)
    : undefined;
}

function scopedKey(
  options: QueriesOptions,
  key: readonly unknown[],
): readonly unknown[] {
  return options.scope === undefined ? key : [...key, { scope: options.scope }];
}

function clientQueries(
  block: string,
  client: object,
  options: QueriesOptions,
): Readonly<Record<string, unknown>> {
  const prefix = [BLOCK_KEY, block] as const;

  const read = (name: string) => {
    const method = methodOf(client, name);

    return (...args: unknown[]) => {
      const skip = args.length === 1 && isSkip(args[0]);

      return {
        queryKey: scopedKey(options, [
          ...prefix,
          name,
          ...(skip ? [] : args.map(keyPart)),
        ]),
        queryFn:
          skip || method === undefined
            ? args[0]
            : () => unwrap(method(...args)),
        meta: { bsTables: [block] },
        ...(options.staleTime === undefined
          ? {}
          : { staleTime: options.staleTime }),
      };
    };
  };

  const write = (name: string) => {
    const method = methodOf(client, name);
    const spread = method !== undefined && method.length > 1;

    return () => ({
      mutationKey: [...prefix, name],
      mutationFn: (variables: unknown) => {
        if (method === undefined) {
          return Promise.reject(
            new TypeError(`${block}.${name} is not a method`),
          );
        }

        if (spread && Array.isArray(variables)) {
          const list: readonly unknown[] = variables;

          return unwrap(method(...list));
        }

        return unwrap(method(variables));
      },
      onSuccess: (
        _data: unknown,
        _variables: unknown,
        _result: unknown,
        context: { readonly client: QueryClient },
      ) => invalidateTables(context.client, [block]),
    });
  };

  const entries: [string, unknown][] = [];
  let current: object | null = client;

  while (current !== null && current !== Object.prototype) {
    for (const name of Object.getOwnPropertyNames(current)) {
      if (
        name !== "constructor" &&
        !entries.some(([known]) => known === name) &&
        typeof memberOf(client, name) === "function"
      ) {
        entries.push([name, isReadName(name) ? read(name) : write(name)]);
      }
    }

    // SAFETY: a prototype is an object or null.
    current = Object.getPrototypeOf(current) as object | null;
  }

  return Object.fromEntries([...entries, ["$key", prefix]]);
}

/**
 * Query options for each read method of each block client (`get*`, `list*`,
 * `find*`, `search*` and the other `BLOCK_READ_PREFIXES`), keyed `["bsb",
 * instance, method, ...args]` like table queries, and mutation options for
 * every other method. A mutation makes its instance's queries stale, through
 * the matcher table writes use (`invalidateTables`); `invalidateOnBlockEvents`
 * does the same for block events. Renamed blocks (`renameBlock`) keep their
 * renamed method names. A method that fails throws a `DbException`, like
 * `createQueries`.
 */
export function blockQueries<const C extends BlockClients>(
  clients: C,
  options: QueriesOptions = {},
): BlockQueries<C> {
  // SAFETY: each entry holds the query or mutation options of every method of
  // the matching client, which is what `BlockQueries<C>` types.
  return Object.fromEntries(
    Object.entries(clients).map(([block, client]) => [
      block,
      clientQueries(block, client, options),
    ]),
  ) as BlockQueries<C>;
}

/** What `invalidateOnBlockEvents` reads from each block. */
export interface BlockInvalidation {
  readonly events: { readonly types: readonly string[] };
  readonly invalidates?: Readonly<Record<string, readonly string[]>>;
}

const matches = (pattern: string, type: string): boolean =>
  pattern.endsWith(".*")
    ? type.startsWith(pattern.slice(0, -1))
    : pattern === type;

/**
 * Makes block queries stale when a block event arrives on `source.events`: the
 * read methods the block's `invalidates` lists for the event, or every read
 * method of the block when none lists it. Pass the blocks keyed like the
 * clients given to `blockQueries` (`defineBlocks(...).blocks`). Returns a
 * function that stops listening.
 */
export function invalidateOnBlockEvents(
  queryClient: QueryClient,
  source: { readonly events: EventHub },
  blocks: Readonly<Record<string, BlockInvalidation>>,
): () => void {
  const owners = new Map<string, string[]>();

  for (const [key, block] of Object.entries(blocks)) {
    for (const type of block.events.types) {
      owners.set(type, [...(owners.get(type) ?? []), key]);
    }
  }

  return source.events.on("block", (event) => {
    for (const key of owners.get(event.type) ?? []) {
      const listed = Object.entries(blocks[key]?.invalidates ?? {})
        .filter(([pattern]) => matches(pattern, event.type))
        .flatMap(([, methods]) => methods);

      void invalidateTables(
        queryClient,
        [key],
        listed.length === 0 ? undefined : new Set(listed),
      );
    }
  });
}
