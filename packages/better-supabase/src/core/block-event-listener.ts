import type {
  BlockEvent,
  BlockEventPattern,
  BlockEventsMatching,
} from "./block-events.ts";
import type { EventMap, Events } from "./event-map.ts";
import type { EventHub } from "./events.ts";

const matches = (pattern: string, type: string): boolean =>
  pattern.endsWith(".*")
    ? type.startsWith(pattern.slice(0, -1))
    : pattern === type;

/**
 * Listens to the block events that match `pattern` (`'support.started'` or
 * `'support.*'`), typed by `events`: a block's events, `defineBlocks(...)` or
 * `defineEvents(...)`. Returns a function that stops listening.
 */
export function onBlockEvent<
  M extends EventMap,
  const P extends BlockEventPattern<M>,
>(
  betterSupabase: { readonly events: EventHub },
  events: Events<M>,
  pattern: P,
  handler: (event: BlockEvent<M, BlockEventsMatching<M, P>>) => void,
): () => void {
  const known = new Set<string>(events.types);

  return betterSupabase.events.on("block", (event) => {
    if (!known.has(event.type) || !matches(pattern, event.type)) {
      return;
    }

    // SAFETY: `events` lists the type, and matches() checked it against the
    // pattern, so the data is the one `M` declares for it.
    handler(event as BlockEvent<M, BlockEventsMatching<M, P>>);
  });
}
