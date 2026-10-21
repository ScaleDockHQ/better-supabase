import { useEffect } from "react";

import type {
  BlockArgsOf,
  BlockDataOf,
  BlockEventSource,
  BlockMethodName,
  BlockMutationActions,
  BlockMutationState,
  BlockQueryActions,
  BlockQueryOptions,
  BlockQueryState,
} from "../blocks/block-controller.ts";
import type {
  BlockEvent,
  BlockEventPattern,
  BlockEventsMatching,
} from "../core/block-events.ts";
import type { EventMap, Events } from "../core/event-map.ts";

import {
  blockArgsKey,
  createBlockMutation,
  createBlockQuery,
  listenToBlockEvents,
} from "../blocks/block-controller.ts";
import { useController, useLatest } from "../blocks/react-controller.ts";

/**
 * Calls a read method of any block client (`blocks.tasks.list`, renamed or not)
 * on mount and when its arguments change. `refetchOn` calls it again on block
 * events.
 */
export function useBlockQuery<
  C extends object,
  const K extends BlockMethodName<C>,
>(
  client: C,
  method: K,
  args: BlockArgsOf<C, K>,
  options: BlockQueryOptions = {},
): BlockQueryState<BlockDataOf<C, K>> & BlockQueryActions {
  return useController(
    () => createBlockQuery(client, method, args, options),
    [client, method, blockArgsKey(args), options.refetchOn?.source],
  ).view;
}

/** Calls a write method of any block client and tracks its state. */
export function useBlockMutation<
  C extends object,
  const K extends BlockMethodName<C>,
>(
  client: C,
  method: K,
): BlockMutationState<BlockDataOf<C, K>> &
  BlockMutationActions<BlockArgsOf<C, K>, BlockDataOf<C, K>> {
  return useController(
    () => createBlockMutation(client, method),
    [client, method],
  ).view;
}

/**
 * Calls `handler` for each block event matching `pattern` (`"task.*"`), typed
 * by `events` (`blockEvents` from `blocks.generated.ts`). `source` is the
 * client's `betterSupabase`.
 */
export function useBlockEvent<
  M extends EventMap,
  const P extends BlockEventPattern<M>,
>(
  source: BlockEventSource,
  events: Events<M>,
  pattern: P,
  handler: (event: BlockEvent<M, BlockEventsMatching<M, P>>) => void,
): void {
  const latest = useLatest(handler);

  useEffect(
    () => listenToBlockEvents(source, events, pattern, () => latest.current),
    [source, events, pattern, latest],
  );
}
