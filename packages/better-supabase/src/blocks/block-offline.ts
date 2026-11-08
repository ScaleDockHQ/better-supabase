import type { DataEngine, DataKey } from "../bindings/data-engine.ts";
import type { Result } from "../core/result.ts";
import type {
  BlockEngineOptions,
  BlockMutationActions,
  BlockMutationState,
  BlockQueryActions,
  BlockQueryOptions,
  BlockQueryState,
  BlockRefetchOn,
} from "./block-controller.ts";
import type {
  BlockArgsOf,
  BlockDataOf,
  BlockMethodName,
} from "./block-method.ts";
import type { Controller } from "./controller.ts";

import { DbException } from "../core/db-exception.ts";
import { BLOCK_KEY } from "./block-controller.ts";
import { methodOf } from "./block-method.ts";
import { defineController } from "./controller.ts";

/** What the offline controllers add to the options of the plain ones. */
export type BlockOfflineOptions = BlockEngineOptions & {
  /**
   * Starts the controller paused, for a component that mounts while the app is
   * already offline. `setOffline` keeps it current afterwards.
   */
  readonly offline?: boolean;
};

export type BlockOfflineQueryOptions = BlockOfflineOptions &
  Pick<BlockQueryOptions, "refetchOn">;

export interface BlockOfflineQueryState<T> extends BlockQueryState<T> {
  /**
   * `true` while the read is paused for lack of a connection: the last data
   * stays, no error is set, and the read runs once when `setOffline(false)` is
   * called. Absent until `setOffline` is first called.
   */
  readonly offline?: boolean;
}

export interface BlockOfflineQueryActions extends BlockQueryActions {
  /**
   * Pauses the controller's reads (`true`) or resumes them (`false`) and runs
   * the one a pause held back. Calling it with the current value changes
   * nothing, so a double effect is safe. Reads kept in a `DataEngine` follow
   * the engine's own online handling and only report the flag.
   */
  readonly setOffline: (offline: boolean) => void;
}

export interface BlockOfflineMutationState<T> extends BlockMutationState<T> {
  /**
   * `true` while a write waits for the connection. The status stays `pending`
   * and the write runs once when `setOffline(false)` is called. Absent until
   * `setOffline` is first called.
   */
  readonly offline?: boolean;
}

export interface BlockOfflineMutationActions<
  A extends readonly unknown[],
  T,
> extends BlockMutationActions<A, T> {
  /**
   * Holds writes while offline (`true`): one write queues, a later call
   * replaces its arguments and shares its promise, and the write runs once on
   * `setOffline(false)`. Calling it with the current value changes nothing.
   */
  readonly setOffline: (offline: boolean) => void;
}

/**
 * Calls one read method of a block client while the controller has listeners,
 * and again on `refetch` or a `refetchOn` event. Works for every block, renamed
 * or not. With `engine`, the read lives in that engine and every controller on
 * the same key shares it.
 */
export function createOfflineBlockQuery<
  C extends object,
  const K extends BlockMethodName<C>,
>(
  client: C,
  method: K,
  args: BlockArgsOf<C, K>,
  options: BlockOfflineQueryOptions = {},
): Controller<
  BlockOfflineQueryState<BlockDataOf<C, K>>,
  BlockOfflineQueryActions
> {
  const call = methodOf(client, method);

  if (options.engine !== undefined) {
    return engineQuery(
      options.engine,
      [BLOCK_KEY, options.instance, method, ...args],
      () => call(...args),
      options.refetchOn,
      options.offline === true,
    );
  }

  const initial: BlockOfflineQueryState<BlockDataOf<C, K>> = {
    status: "idle",
    data: undefined,
    error: undefined,
    ...(options.offline ? { offline: true } : {}),
  };

  return defineController(initial, (state) => {
    let offline = options.offline === true;
    let held = false;

    const load = (): void => {
      if (offline) {
        held = true;

        return;
      }

      held = false;
      const run = state.run();
      state.set({ status: "loading" });

      void Promise.resolve(call(...args)).then((result) => {
        if (run !== state.run()) {
          return result;
        }

        if (!result.ok && offline) {
          // The connection dropped mid-read: keep the last data, show no error.
          held = true;
          state.set({
            status: state.get().data === undefined ? "idle" : "success",
          });

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

    const setOffline = (next: boolean): void => {
      if (next === offline) {
        return;
      }

      offline = next;
      state.set({ offline: next });

      if (!next && held) {
        load();
      }
    };

    return {
      actions: { refetch: load, setOffline },
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

function engineQuery<T>(
  engine: DataEngine,
  key: DataKey,
  call: () => PromiseLike<Result<unknown>>,
  refetchOn: BlockRefetchOn | undefined,
  offline: boolean,
): Controller<BlockOfflineQueryState<T>, BlockOfflineQueryActions> {
  // SAFETY: the entry under `key` holds what this method's `Result` carries.
  const read = (): BlockOfflineQueryState<T> =>
    engine.entry(key) as BlockQueryState<T>;

  const load = async (): Promise<unknown> => {
    const result = await call();

    if (!result.ok) {
      throw new DbException(result.error);
    }

    return result.data;
  };

  return defineController(
    offline ? { ...read(), offline: true } : read(),
    (state) => ({
      actions: {
        refetch: () => {
          if (!state.get().offline) {
            engine.refetch(key);
          }
        },
        setOffline: (offline) => {
          state.set({ offline });
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
          if (types.has(event.type) && !state.get().offline) {
            engine.refetch(key);
          }
        });

        return () => {
          stopListening();
          stopWatching();
        };
      },
    }),
  );
}

/**
 * Calls one write method of a block client and tracks its state. With `engine`,
 * a write that succeeds makes the instance's reads in it stale.
 */
export function createOfflineBlockMutation<
  C extends object,
  const K extends BlockMethodName<C>,
>(
  client: C,
  method: K,
  options: BlockOfflineOptions = {},
): Controller<
  BlockOfflineMutationState<BlockDataOf<C, K>>,
  BlockOfflineMutationActions<BlockArgsOf<C, K>, BlockDataOf<C, K>>
> {
  const call = methodOf(client, method);

  const initial: BlockOfflineMutationState<BlockDataOf<C, K>> = {
    status: "idle",
    data: undefined,
    error: undefined,
    ...(options.offline ? { offline: true } : {}),
  };

  return defineController(initial, (state) => {
    let latest = 0;
    let offline = options.offline === true;

    let queued:
      | {
          args: BlockArgsOf<C, K>;
          readonly promise: Promise<Result<BlockDataOf<C, K>>>;
          readonly settle: (result: Result<BlockDataOf<C, K>>) => void;
        }
      | undefined;

    const send = async (
      args: BlockArgsOf<C, K>,
    ): Promise<Result<BlockDataOf<C, K>>> => {
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
    };

    const queue = (
      args: BlockArgsOf<C, K>,
    ): Promise<Result<BlockDataOf<C, K>>> => {
      if (queued) {
        queued.args = args;

        return queued.promise;
      }

      let settle: (result: Result<BlockDataOf<C, K>>) => void = () => undefined;

      const promise = new Promise<Result<BlockDataOf<C, K>>>((resolve) => {
        settle = resolve;
      });

      queued = { args, promise, settle };
      latest += 1;
      state.set({ status: "pending", error: undefined });

      return promise;
    };

    return {
      actions: {
        mutate: (...args) => (offline ? queue(args) : send(args)),
        reset: () => {
          latest += 1;

          if (queued) {
            queued.settle({
              ok: false,
              data: null,
              error: {
                kind: "network",
                message: "The queued write was cancelled.",
                status: 503,
              },
            });
            queued = undefined;
          }

          state.set({ ...initial, ...(offline ? { offline } : {}) });
        },
        setOffline: (next) => {
          if (next === offline) {
            return;
          }

          offline = next;
          state.set({ offline: next });

          if (!next && queued) {
            const { args, settle } = queued;
            queued = undefined;
            void send(args).then(settle);
          }
        },
      },
    };
  });
}
