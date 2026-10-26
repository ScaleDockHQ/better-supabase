import type { QueryClient, SkipToken } from "@tanstack/query-core";

import type { PermissionSet } from "../blocks/permissions/permissions-controller.ts";
import type {
  RecordBindingData,
  RecordBindingOptions,
  RecordBindingResult,
} from "../blocks/record-bindings.ts";
import type { EventHub } from "../core/events.ts";
import type { AsyncResult, Result } from "../core/result.ts";
import type {
  BindingName,
  BindingOf,
  BindingSource,
} from "../records/bindings.ts";
import type {
  RecordTypeBlocks,
  RecordTypeWriteInput,
  RecordTypeWriteOutput,
  RecordCan,
  RecordType,
  BindingWritesOf,
} from "../records/record-type.ts";
import type {
  MutationOptionsOf,
  QueriesOptions,
  QueryOptionsOf,
} from "./queries.ts";

import { recordEventMatches } from "../blocks/record-bindings.ts";
import { DbException } from "../core/errors.ts";
import { findBinding, loadBindings } from "../records/bindings.ts";
import {
  bindingWrites,
  recordCan,
  recordPermissionKeys,
  recordSubject,
  runBindingWrite,
} from "../records/record-type.ts";
import { keyPart } from "./queries.ts";

/** The first key part of every record query. */
const RECORD_KEY = "bsb-record";

/** The key part of a record's `can` query. */
const CAN_KEY = "$can";

/** Query options for each binding of a record type, by binding name. */
export type RecordBindingQueries<
  B extends RecordTypeBlocks,
  N extends string,
> = {
  readonly [S in N]: (
    id: string | SkipToken,
    options?: RecordBindingOptions<BindingOf<B, S>>,
  ) => QueryOptionsOf<RecordBindingData<BindingOf<B, S>>>;
};

/** Mutation options for each write of each binding, by binding and write. */
export type RecordWriteMutations<
  B extends RecordTypeBlocks,
  N extends string,
> = {
  readonly [S in N]: {
    readonly [W in BindingWritesOf<B, S>]: (
      id: string,
    ) => MutationOptionsOf<
      RecordTypeWriteInput<B, S, W>,
      RecordTypeWriteOutput<B, S, W>
    >;
  };
};

export interface RecordQueries<
  T extends string,
  B extends RecordTypeBlocks,
  N extends string,
> {
  /** Prefix of every key of this record type's queries. */
  readonly $key: readonly [typeof RECORD_KEY, T];
  /** The key of one record's queries, or of one of its bindings. */
  key(id: string, binding?: N): readonly unknown[];
  /** Query options per binding, keyed `["bsb-record", type, id, binding]`. */
  readonly bindings: RecordBindingQueries<B, N>;
  /**
   * Mutation options per binding write; each one makes the binding's queries of
   * that record stale.
   */
  readonly writes: RecordWriteMutations<B, N>;
  /** What the caller may do on each binding, from the `access` client. */
  can(): QueryOptionsOf<RecordCan<B, N>>;
}

export interface RecordQueriesOptions extends QueriesOptions {
  /**
   * The permissions block's client, which loads the caller's keys for `can`.
   * Without it every flag is `true` and RLS decides.
   */
  readonly access?: {
    permissions(keys: readonly string[]): AsyncResult<PermissionSet>;
  };
}

function scoped(
  options: QueriesOptions,
  key: readonly unknown[],
): readonly unknown[] {
  return options.scope === undefined ? key : [...key, { scope: options.scope }];
}

async function unwrap<T>(result: PromiseLike<Result<T>>): Promise<T> {
  const settled = await result;

  if (!settled.ok) {
    throw new DbException(settled.error);
  }

  return settled.data;
}

/**
 * TanStack Query bindings of a generated record type, for apps that load
 * records on the client (Vite, Expo, TanStack Start): query options per
 * binding, mutation options per binding write, and the caller's `can` flags.
 * Pass the block clients keyed like the record type's blocks, such as
 * `blocks(supabase)` from `lib/blocks.ts`. A binding that fails throws a
 * `DbException`, like `blockQueries`.
 *
 * ```ts
 * const customer = recordQueries(customerRecord, clients);
 * const comments = useQuery(customer.bindings.comments(id));
 * const add = useMutation(customer.writes.comments.add(id));
 * ```
 */
export function recordQueries<
  T extends string,
  B extends RecordTypeBlocks,
  N extends BindingName<B>,
>(
  feature: RecordType<T, B> & { readonly bindings: readonly N[] },
  clients: object,
  options: RecordQueriesOptions = {},
): RecordQueries<T, B, N> {
  const prefix = [RECORD_KEY, feature.type] as const;
  const names: readonly N[] = feature.bindings;

  const source: BindingSource<B> = { blocks: feature.blocks, clients };

  const keyOf = (id: string, binding?: string): readonly unknown[] =>
    binding === undefined ? [...prefix, id] : [...prefix, id, binding];

  const stale =
    options.staleTime === undefined ? {} : { staleTime: options.staleTime };

  const binding =
    (name: N) =>
    (id: string | SkipToken, given?: unknown): QueryOptionsOf<unknown> => {
      const skip = typeof id !== "string";

      const queryKey = scoped(options, [
        ...prefix,
        ...(skip ? [] : [id, name]),
        ...(given === undefined ? [] : [keyPart(given)]),
      ]);

      // SAFETY: the key is tagged with the binding's data, which `queryFn`
      // resolves to.
      return {
        queryKey: queryKey as QueryOptionsOf<unknown>["queryKey"],
        queryFn: skip
          ? id
          : async () => {
              const loaded: Readonly<
                Record<string, RecordBindingResult<unknown>>
              > = await loadBindings(
                source,
                recordSubject(feature, id),
                [name],
                // SAFETY: `given` is the options the binding's `load` takes.
                given === undefined
                  ? {}
                  : { options: { [name]: given } as never },
              );

              const result = loaded[name];

              if (result?.kind === "error") {
                throw new DbException(result.error);
              }

              return result?.kind === "ok" ? result.data : undefined;
            },
        meta: { bsTables: [] },
        ...stale,
      };
    };

  const write =
    (name: string, writeName: string) =>
    (id: string): MutationOptionsOf<unknown, unknown> => ({
      mutationKey: [...prefix, id, name, writeName],
      mutationFn: (input) =>
        unwrap(
          runBindingWrite(
            feature,
            clients,
            name,
            writeName,
            recordSubject(feature, id),
            input,
          ),
        ),
      onSuccess: (_data, _input, _result, context) =>
        context.client.invalidateQueries({ queryKey: keyOf(id, name) }),
    });

  // SAFETY: one query option per binding and one mutation option per write,
  // as `RecordBindingQueries` and `RecordWriteMutations` map them.
  return {
    $key: prefix,
    key: keyOf,
    bindings: Object.fromEntries(
      names.map((name) => [name, binding(name)]),
    ) as never,
    writes: Object.fromEntries(
      bindingWrites(feature).map(([name, writes]) => [
        name,
        Object.fromEntries(
          writes.map((writeName) => [writeName, write(name, writeName)]),
        ),
      ]),
    ) as never,
    can: () =>
      // SAFETY: the key is tagged with `RecordCan`, which `queryFn` resolves to.
      ({
        queryKey: scoped(options, [...prefix, CAN_KEY]) as never,
        queryFn: async () => {
          const keys = recordPermissionKeys(feature);

          const set =
            options.access === undefined || keys.length === 0
              ? undefined
              : await unwrap(options.access.permissions(keys));

          return recordCan<B, N>(feature, set);
        },
        meta: { bsTables: [] },
        ...stale,
      }),
  };
}

/**
 * Makes a record type's binding queries stale when a block event that the
 * binding lists in `events` arrives on `source.events`, for every record of the
 * record type. Returns a function that stops listening.
 */
export function invalidateOnRecordEvents(
  queryClient: QueryClient,
  source: { readonly events: EventHub },
  feature: Pick<RecordType, "blocks" | "type"> & {
    readonly bindings: readonly string[];
  },
): () => void {
  const patterns = feature.bindings.map(
    (name) =>
      [name, findBinding(feature.blocks, name)?.binding.events ?? []] as const,
  );

  return source.events.on("block", (event) => {
    const names = new Set(
      patterns
        .filter(([, events]) =>
          events.some((pattern) => recordEventMatches(pattern, event.type)),
        )
        .map(([name]) => name),
    );

    if (names.size === 0) {
      return;
    }

    void queryClient.invalidateQueries({
      predicate: ({ queryKey }) =>
        queryKey[0] === RECORD_KEY &&
        queryKey[1] === feature.type &&
        names.has(String(queryKey[3])),
    });
  });
}
