import type { DataEngine, DataKey } from "../bindings/data-engine.ts";
import type {
  BlockEvent,
  BlockEventPattern,
  BlockEventsMatching,
} from "../core/block-events.ts";
import type { DbError } from "../core/errors.ts";
import type { EventMap, Events } from "../core/event-map.ts";
import type { EventHub } from "../core/events.ts";
import type { Result } from "../core/result.ts";
import type {
  BlockArgsOf,
  BlockDataOf,
  BlockMethodName,
} from "./block-method.ts";
import type { Controller } from "./controller.ts";

import { onBlockEvent } from "../core/block-event-listener.ts";
import { DbException } from "../core/db-exception.ts";
import { methodOf } from "./block-method.ts";
import { defineController } from "./controller.ts";

export type {
  BlockArgsOf,
  BlockDataOf,
  BlockMethodName,
} from "./block-method.ts";

/** A block read's state: the last data stays while it loads again. */
export interface BlockQueryState<T> {
  readonly status: "idle" | "loading" | "success" | "error";
  readonly data: T | undefined;
  readonly error: DbError | undefined;
}

export interface BlockQueryActions {
  /** Calls the method again. */
  readonly refetch: () => void;
}

/** Where a block read hears the events that make it stale. */
export interface BlockRefetchOn {
  readonly source: { readonly events: EventHub };
  /** The event types, such as `blockEvents.types` from `blocks.generated.ts`. */
  readonly types: readonly string[];
}

/**
 * Keeps a block's reads in a data engine, keyed `["bsb", instance, method,
 * ...args]`: `blockControllerEngine(queryClient)` from `better-supabase/query`
 * shares them with `blockQueries`. `instance` is the block's key in
 * `createBlocks`.
 */
export type BlockEngineOptions =
  | { readonly engine?: undefined }
  | { readonly engine: DataEngine; readonly instance: string };

export type BlockQueryOptions = BlockEngineOptions & {
  /** Calls the method again when one of these block events arrives. */
  readonly refetchOn?: BlockRefetchOn;
};

/**
 * Calls one read method of a block client while the controller has listeners,
 * and again on `refetch` or a `refetchOn` event. Works for every block, renamed
 * or not. With `engine`, the read lives in that engine and every controller on
 * the same key shares it.
 */
export function createBlockQuery<
  C extends object,
  const K extends BlockMethodName<C>,
>(
  client: C,
  method: K,
  args: BlockArgsOf<C, K>,
  options: BlockQueryOptions = {},
): Controller<BlockQueryState<BlockDataOf<C, K>>, BlockQueryActions> {
  const call = methodOf(client, method);

  if (options.engine !== undefined) {
    return engineQuery(
      options.engine,
      [BLOCK_KEY, options.instance, method, ...args],
      () => call(...args),
      options.refetchOn,
    );
  }

  const initial: BlockQueryState<BlockDataOf<C, K>> = {
    status: "idle",
    data: undefined,
    error: undefined,
  };

  return defineController(initial, (state) => {
    const load = (): void => {
      const run = state.run();
      state.set({ status: "loading" });

      void Promise.resolve(call(...args)).then((result) => {
        if (run !== state.run()) {
          return result;
        }

        // SAFETY: the method's `Result` carries `BlockDataOf<C, K>`.
        state.set(
          result.ok
            ? {
                status: "success",
                data: result.data as BlockDataOf<C, K>,
                error: undefined,
              }
            : { status: "error", error: result.error },
        );

        return result;
      });
    };

    return {
      actions: { refetch: load },
      start: () => {
        load();

        const refetchOn = options.refetchOn;

        if (refetchOn === undefined) {
          return;
        }

        const types = new Set(refetchOn.types);

        return refetchOn.source.events.on("block", (event) => {
          if (types.has(event.type)) {
            load();
          }
        });
      },
    };
  });
}

const BLOCK_KEY = "bsb";

function engineQuery<T>(
  engine: DataEngine,
  key: DataKey,
  call: () => PromiseLike<Result<unknown>>,
  refetchOn: BlockRefetchOn | undefined,
): Controller<BlockQueryState<T>, BlockQueryActions> {
  // SAFETY: the entry under `key` holds what this method's `Result` carries.
  const read = (): BlockQueryState<T> =>
    engine.entry(key) as BlockQueryState<T>;

  const load = async (): Promise<unknown> => {
    const result = await call();

    if (!result.ok) {
      throw new DbException(result.error);
    }

    return result.data;
  };

  return defineController(read(), (state) => ({
    actions: {
      refetch: () => {
        engine.refetch(key);
      },
    },
    start: () => {
      const stopWatching = engine.watch(key, load, () => {
        state.set(read());
      });

      state.set(read());

      if (refetchOn === undefined) {
        return stopWatching;
      }

      const types = new Set(refetchOn.types);

      const stopListening = refetchOn.source.events.on("block", (event) => {
        if (types.has(event.type)) {
          engine.refetch(key);
        }
      });

      return () => {
        stopListening();
        stopWatching();
      };
    },
  }));
}

/** A block write's state. */
export interface BlockMutationState<T> {
  readonly status: "idle" | "pending" | "success" | "error";
  readonly data: T | undefined;
  readonly error: DbError | undefined;
}

export interface BlockMutationActions<A extends readonly unknown[], T> {
  /** Calls the method; the `Result` resolves when it settles. */
  readonly mutate: (...args: A) => Promise<Result<T>>;
  /** Back to `idle`. */
  readonly reset: () => void;
}

/**
 * Calls one write method of a block client and tracks its state. With `engine`,
 * a write that succeeds makes the instance's reads in it stale.
 */
export function createBlockMutation<
  C extends object,
  const K extends BlockMethodName<C>,
>(
  client: C,
  method: K,
  options: BlockEngineOptions = {},
): Controller<
  BlockMutationState<BlockDataOf<C, K>>,
  BlockMutationActions<BlockArgsOf<C, K>, BlockDataOf<C, K>>
> {
  const call = methodOf(client, method);

  const initial: BlockMutationState<BlockDataOf<C, K>> = {
    status: "idle",
    data: undefined,
    error: undefined,
  };

  return defineController(initial, (state) => {
    let latest = 0;

    return {
      actions: {
        mutate: async (...args) => {
          latest += 1;
          const mine = latest;
          state.set({ status: "pending", error: undefined });

          // SAFETY: the method's `Result` carries `BlockDataOf<C, K>`.
          const result = (await call(...args)) as Result<BlockDataOf<C, K>>;

          if (result.ok && options.engine !== undefined) {
            options.engine.invalidate([BLOCK_KEY, options.instance]);
          }

          if (mine === latest) {
            state.set(
              result.ok
                ? { status: "success", data: result.data, error: undefined }
                : { status: "error", error: result.error },
            );
          }

          return result;
        },
        reset: () => {
          latest += 1;
          state.set(initial);
        },
      },
    };
  });
}

/**
 * A stable key for a method's arguments, so a hook makes a new controller only
 * when they change. A `bigint` becomes its digits.
 */
export function blockArgsKey(args: readonly unknown[]): string {
  return JSON.stringify(args, (_key, value: unknown) =>
    typeof value === "bigint" ? `${value.toString()}n` : value,
  );
}

/** What `useBlockEvent` listens to: the client's `betterSupabase`. */
export interface BlockEventSource {
  readonly events: EventHub;
}

/**
 * Listens to the block events matching `pattern`, typed by `events`
 * (`blockEvents` from `blocks.generated.ts`), calling `handler()` for the
 * latest handler. Returns the function that stops listening.
 */
export function listenToBlockEvents<
  M extends EventMap,
  const P extends BlockEventPattern<M>,
>(
  source: BlockEventSource,
  events: Events<M>,
  pattern: P,
  handler: () => (event: BlockEvent<M, BlockEventsMatching<M, P>>) => void,
): () => void {
  return onBlockEvent(source, events, pattern, (event) => {
    handler()(event);
  });
}
