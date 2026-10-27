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

export interface BlockQueryOptions {
  /** Calls the method again when one of these block events arrives. */
  readonly refetchOn?: BlockRefetchOn;
}

/**
 * Calls one read method of a block client while the controller has listeners,
 * and again on `refetch` or a `refetchOn` event. Works for every block, renamed
 * or not.
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

/** Calls one write method of a block client and tracks its state. */
export function createBlockMutation<
  C extends object,
  const K extends BlockMethodName<C>,
>(
  client: C,
  method: K,
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
