/**
 * Event maps: the types a block or an app emits and the data of each. Kept
 * apart from `block-events.ts` so a block's `events.ts` pulls in no runtime
 * beyond `defineEvents`.
 */

/** Event type to its data, such as `{ "message.sent": MessageEventData }`. */
export type EventMap = { readonly [type: string]: object };

declare const EVENT_DATA: unique symbol;

/** One event in `defineEvents`, carrying only its data type. */
export interface EventSpec<T extends object> {
  readonly [EVENT_DATA]?: T;
  /** `true` when the event is part of the block's public webhook catalog. */
  readonly public?: boolean;
}

/** What `event` takes besides the data type. */
export interface EventOptions {
  /**
   * `true` marks the event as one an app may expose to webhook subscribers (ADR
   * 0919). `webhookEventCatalog` lists these.
   */
  readonly public?: boolean;
}

/** The event `type` and its data type `T`, for `defineEvents`. */
/*#__NO_SIDE_EFFECTS__*/
export function event<T extends object>(options?: EventOptions): EventSpec<T> {
  return options?.public === true ? { public: true } : {};
}

/**
 * A set of event types and, in its type, their data: a block's own events (the
 * manifest's `events`) or the app's (`defineEvents`). `types` lists the types
 * at runtime.
 */
export interface Events<M extends EventMap = EventMap> {
  /** The event types, the keys of `M`. */
  readonly types: readonly string[];
  /** The types marked `public`: the block's webhook event catalog. */
  readonly public?: readonly string[];
  /** Carries `M` in the type only; always absent. */
  readonly "~map"?: M;
}

/** The event map an `Events` value carries. */
export type EventMapOf<E> = E extends Events<infer M> ? M : never;

type DataOf<S> = S extends EventSpec<infer T> ? T : never;

/**
 * Declares events by type, so blocks, `defineBlocks` and `onBlockEvent` type
 * their data: `defineEvents({ "invoice.sent": event<{ invoiceId: string }>()
 * })`.
 */
/*#__NO_SIDE_EFFECTS__*/
export function defineEvents<
  const S extends Readonly<Record<string, EventSpec<object>>>,
>(spec: S): Events<{ readonly [K in keyof S & string]: DataOf<S[K]> }> {
  const types = Object.keys(spec);
  const published = types.filter((type) => spec[type]?.public === true);

  return published.length === 0 ? { types } : { types, public: published };
}

type UnionToIntersection<U> = (
  U extends unknown ? (value: U) => void : never
) extends (value: infer I) => void
  ? I
  : never;

/** One map with the events of every `Events` in the tuple. */
export type MergedEventMap<E extends readonly Events[]> = E extends readonly []
  ? Record<never, never>
  : UnionToIntersection<EventMapOf<E[number]>> extends infer M extends EventMap
    ? M
    : never;

/** Several `Events` as one, such as a block's events and the app's own. */
export function mergeEvents<const E extends readonly Events[]>(
  ...events: E
): Events<MergedEventMap<E>> {
  const types = [...new Set(events.flatMap((each) => each.types))];

  const published = [...new Set(events.flatMap((each) => each.public ?? []))];

  return published.length === 0 ? { types } : { types, public: published };
}
