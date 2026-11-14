import type { Events } from "../core/event-map.ts";

/** One event a block marks `public`, as the webhook event catalog lists it. */
export interface WebhookCatalogEntry {
  /** The block that emits it. */
  readonly block: string;
  /** The event type, such as `invoice.paid`. */
  readonly type: string;
}

/** What `webhookEventCatalog` reads from a block manifest. */
export interface WebhookCatalogSource {
  readonly name: string;
  readonly events: Events;
}

/**
 * The events the blocks mark `public` (`event<T>({ public: true })`, ADR 0919),
 * sorted by block and type. An endpoint's `events` filter and the app's own
 * documentation read it, so a webhook subscriber is offered only the events a
 * block means to expose.
 */
export function webhookEventCatalog(
  blocks: readonly WebhookCatalogSource[],
): readonly WebhookCatalogEntry[] {
  return blocks
    .flatMap((block) =>
      (block.events.public ?? []).map((type) => ({ block: block.name, type })),
    )
    .toSorted(
      (a, b) => a.block.localeCompare(b.block) || a.type.localeCompare(b.type),
    );
}
