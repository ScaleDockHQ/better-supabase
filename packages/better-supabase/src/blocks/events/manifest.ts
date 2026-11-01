import type { BlockContext } from "../create-blocks.ts";
import type { BlockOf, CompositeOptions } from "../define-block.ts";

import { bookingsBlock } from "../bookings/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { passesBlock } from "../passes/manifest.ts";

/** The blocks `events` is made of, by block name. */
export const eventsParts: {
  readonly bookings: typeof bookingsBlock;
  readonly passes: typeof passesBlock;
} = { bookings: bookingsBlock, passes: passesBlock };

export type EventsParts = typeof eventsParts;

/**
 * The `events` composite (ADR 0177): bookings and admission passes for events.
 * It installs its parts and sets their defaults; the parts stay ordinary blocks
 * in the config.
 */
export const eventsBlock: BlockOf<
  "events",
  (options: BlockContext & CompositeOptions<EventsParts>) => undefined
> = defineBlock({
  name: "events",
  composes: eventsParts,
  category: "scheduling",
});
