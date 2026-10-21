import { onCleanup, onMount } from "solid-js";

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
import type { SolidController } from "../blocks/solid-bind.ts";
import type {
  BlockEvent,
  BlockEventPattern,
  BlockEventsMatching,
} from "../core/block-events.ts";
import type { EventMap, Events } from "../core/event-map.ts";

import {
  createBlockMutation,
  createBlockQuery,
  listenToBlockEvents,
} from "../blocks/block-controller.ts";
import { bindSolidController } from "../blocks/solid-bind.ts";

/**
 * Calls a read method of any block client (`blocks.tasks.list`, renamed or not)
 * from mount. `refetchOn` calls it again on block events.
 */
export function useBlockQuery<
  C extends object,
  const K extends BlockMethodName<C>,
>(
  client: C,
  method: K,
  args: BlockArgsOf<C, K>,
  options: BlockQueryOptions = {},
): SolidController<BlockQueryState<BlockDataOf<C, K>>, BlockQueryActions> {
  return bindSolidController(createBlockQuery(client, method, args, options));
}

/** Calls a write method of any block client and tracks its state. */
export function useBlockMutation<
  C extends object,
  const K extends BlockMethodName<C>,
>(
  client: C,
  method: K,
): SolidController<
  BlockMutationState<BlockDataOf<C, K>>,
  BlockMutationActions<BlockArgsOf<C, K>, BlockDataOf<C, K>>
> {
  return bindSolidController(createBlockMutation(client, method));
}

/**
 * Calls `handler` for each block event matching `pattern` (`"task.*"`), typed
 * by `events` (`blockEvents` from `blocks.generated.ts`), from mount until the
 * component goes away. `source` is the client's `betterSupabase`.
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
  onMount(() => {
    const stop = listenToBlockEvents(source, events, pattern, () => handler);

    onCleanup(stop);
  });
}
