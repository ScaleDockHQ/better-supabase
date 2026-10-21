import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { FieldsOf, RowFields } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  AuthorizationHooks,
  SubscriberPolicy,
} from "../../core/contracts/authorization-hooks.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { EventHub } from "../../core/events.ts";
import type { RequestContext } from "../../core/plugin.ts";
import type { AsyncResult, Result } from "../../core/result.ts";
import type { CloudEvent, EventSink } from "../../events/cloud-event.ts";
import type { BlockTemporalOptions, CursorPageOptions } from "../shared.ts";
import type { NotificationChannel } from "./channel.ts";
import type { EmailChannelOptions } from "./email.ts";
import type {
  NotificationItem,
  NotificationSubject,
  RenderedText,
} from "./types.ts";

/** Notification type to the Standard Schema of its `data`. */
export type NotificationTypes = Readonly<Record<string, StandardSchemaV1>>;

export type TypeName<K extends NotificationTypes> = keyof K & string;

export interface SendInput<
  D = unknown,
  F extends object = Record<never, never>,
> {
  /**
   * Who gets it. Watchers of `subject` and the `notification_audience` hook add
   * more.
   */
  readonly recipients?: readonly string[];
  /**
   * Also notify the users who hold this permission in `tenant`. Needs `tenant`.
   * Without a holders template the send is refused.
   */
  readonly permission?: string;
  /** The organization; required when an authenticated user sends. */
  readonly tenant?: string;
  readonly subject?: NotificationSubject;
  readonly summary?: string;
  readonly actionPath?: string;
  /** One of `blocks.notifications.options.priorities`. Defaults to `normal`. */
  readonly priority?: string;
  readonly data: D;
  /** With a key, sending again (per tenant) returns the first notification. */
  readonly key?: string;
  /** Defaults to `blocks.notifications.options.channels`. */
  readonly channels?: readonly string[];
  /** Also notify the user who caused it. Defaults to `false`. */
  readonly includeActor?: boolean;
  /**
   * `participating` (default) reaches subject watchers at both levels; `all` is
   * routine activity that only `all` watchers get.
   */
  readonly activity?: "participating" | "all";
  /** Create it already resolved, e.g. for a record of a finished approval. */
  readonly resolved?: boolean;
  /** The actor, when the service sends on a user's behalf. */
  readonly actorId?: string;
  /**
   * Add the watchers of `subject`. Defaults to `true`; `false` reaches only
   * `recipients` and the audience hook (members ignoring the subject stay out
   * either way).
   */
  readonly watchers?: boolean;
  /** Users left out after the watchers and the audience hook are added. */
  readonly exclude?: readonly string[];
  /** Values for the events table's extra columns (`options.extraColumns`). */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

export interface ListOptions<
  K extends string = string,
> extends CursorPageOptions<
  Temporal.Instant | Pick<NotificationItem, "createdAt" | "id">
> {
  readonly tenant?: string;
  readonly status?: "all" | "unread" | "read" | "unresolved" | "settled";
  readonly read?: boolean;
  readonly resolved?: boolean;
  readonly dismissed?: boolean | null;
  readonly types?: readonly K[];
  readonly subjectTypes?: readonly string[];
  readonly search?: string;
  /**
   * Page: only notifications older than this. Pass the last item of the
   * previous page; a bare instant skips items created at that same instant.
   */
  readonly cursor?:
    | Temporal.Instant
    | Pick<NotificationItem, "createdAt" | "id">;
  /** Up to 200. Defaults to 50. */
  readonly limit?: number;
  /** Passed to `render`. */
  readonly locale?: string;
  /**
   * `actor` adds each item's actor profile (`id` and the public profile
   * columns), read in one call from the `profiles` module's table.
   */
  readonly include?: readonly "actor"[];
}

export interface PageOptions<K extends string = string> extends Omit<
  ListOptions<K>,
  "before" | "cursor"
> {
  readonly offset?: number;
}

export interface NotificationPage<
  K extends string = string,
  R extends Rendered<K> = Rendered<K>,
> {
  readonly items: readonly R[];
  readonly total: number;
}

export interface NotificationSubscription {
  readonly subject: { readonly type: string; readonly id: string };
  readonly level: SubscriptionLevel;
  readonly tenant: string | null;
  readonly createdAt: Temporal.Instant | null;
}

export interface NotificationPreference {
  readonly type: string;
  readonly channel: string;
  readonly enabled: boolean;
  readonly tenant: string | null;
}

/** The actor of a notification, from the `profiles` module's table. */
export interface NotificationActor {
  readonly id: string;
  readonly username?: string | null;
  readonly fullName?: string | null;
  readonly firstName?: string | null;
  readonly lastName?: string | null;
  readonly avatar?: string | null;
  readonly avatarPath?: string | null;
  readonly avatarUrl?: string | null;
}

export type AvatarUrls =
  | { readonly url: string; readonly bucket: string }
  | ((path: string) => string | null);

export interface SentNotification {
  readonly id: string;
  readonly recipients: readonly string[];
}

export interface NotificationUpdate {
  readonly count: number;
  readonly items: readonly NotificationItem[];
}

export interface NotificationCounts {
  readonly unread: number;
  /** Unresolved notifications of the `actionable` types. */
  readonly actionable: number;
  readonly actionableSubjects: number;
}

export type SubscriptionLevel = "participating" | "all" | "ignore";

export interface DeliverOptions {
  /** Channel names to work on. Defaults to every channel in `channels`. */
  readonly channels?: readonly string[];
  /** Deliveries per claim. Defaults to 50. */
  readonly batch?: number;
  /** How long a claimed delivery waits before another worker retries it. */
  readonly lease?: string;
  /**
   * Tries before a delivery is `failed`. Defaults to 5. Retries wait a random
   * time up to 30 seconds, doubling per attempt to an hour.
   */
  readonly maxAttempts?: number;
  readonly budgetMs?: number;
}

export interface DeliverResult {
  readonly sent: number;
  /**
   * Deliveries not sent on purpose: the channel skipped them, the address is
   * suppressed, or `audience` left the recipient out.
   */
  readonly skipped: number;
  /**
   * Deliveries that threw, or whose `audience` check threw; retried later
   * unless they ran out of attempts.
   */
  readonly failed: number;
}

export type SuppressionReason = "bounce" | "complaint" | "manual";

/**
 * An address a channel stops sending to, written by a bounce or complaint
 * webhook.
 */
export interface SuppressInput {
  /** Stored in lower case. */
  readonly address: string;
  readonly reason: SuppressionReason;
  /** Defaults to `email`. */
  readonly channel?: string;
  /** The provider that reported it, e.g. `resend`. */
  readonly provider?: string;
  /** The provider's event or webhook message id. */
  readonly providerEventId?: string;
  readonly detail?: Readonly<Record<string, unknown>>;
}

export interface NotificationSuppression {
  readonly channel: string;
  readonly address: string;
  /** The user with that address when it was suppressed, or `null`. */
  readonly userId: string | null;
  readonly reason: SuppressionReason;
  readonly provider: string | null;
  readonly createdAt: Temporal.Instant | null;
}

/** What a provider reported about a sent message. */
export type DeliveryEventKind =
  | "delivered"
  | "opened"
  | "clicked"
  | "bounced"
  | "complained"
  | "delayed";

/** One provider event for `recordDeliveryEvent`, usually from a webhook. */
export interface DeliveryEventInput {
  /** The provider the delivery was sent with, e.g. `resend`. */
  readonly provider: string;
  /** The provider's id for the message, as the channel returned it. */
  readonly providerMessageId: string;
  readonly kind: DeliveryEventKind;
  /** The provider's event or webhook message id; the same id is stored once. */
  readonly providerEventId?: string;
  /** When the provider saw it. Defaults to now. */
  readonly occurredAt?: Temporal.Instant;
  readonly detail?: Readonly<Record<string, unknown>>;
  /**
   * Whether a `bounced` or `complained` event suppresses the recipient's
   * address. Defaults to `true`; pass `false` for a soft bounce.
   */
  readonly suppress?: boolean;
}

/** The delivery a provider event was recorded on. */
export interface RecordedDeliveryEvent {
  readonly deliveryId: string;
  readonly notificationId: string;
  readonly tenant: string | null;
  readonly type: string;
  readonly channel: string;
  readonly userId: string | null;
  /** The notification's subject, or `notification` and its id without one. */
  readonly subject: { readonly type: string; readonly id: string };
  readonly kind: DeliveryEventKind;
  /** The delivery's furthest provider status after this event. */
  readonly providerStatus: DeliveryEventKind | null;
  /** `false` when the provider event id was already stored. */
  readonly recorded: boolean;
}

/** One stored provider event of a delivery. */
export interface DeliveryEvent {
  readonly kind: DeliveryEventKind;
  readonly occurredAt: Temporal.Instant | null;
  readonly detail: Readonly<Record<string, unknown>>;
}

/** A delivery of a notification about one record, for `subjectDeliveries`. */
export interface SubjectDelivery {
  readonly id: string;
  readonly notificationId: string;
  readonly type: string;
  readonly channel: string;
  readonly userId: string;
  readonly status: "pending" | "sent" | "failed" | "skipped";
  readonly provider: string | null;
  readonly providerMessageId: string | null;
  readonly providerStatus: DeliveryEventKind | null;
  readonly providerStatusAt: Temporal.Instant | null;
  readonly templateKey: string | null;
  readonly error: string | null;
  readonly attempts: number | null;
  readonly createdAt: Temporal.Instant | null;
  readonly deliveredAt: Temporal.Instant | null;
  /** Oldest first. */
  readonly events: readonly DeliveryEvent[];
}

export interface Rendered<
  K extends string = string,
  D = unknown,
> extends NotificationItem<K, D> {
  /** What `render` returned. Absent without a `render` option. */
  readonly text?: RenderedText;
  /** With `include: ['actor']`: the actor's profile, or null. */
  readonly actor?: NotificationActor | null;
}

/**
 * A notification as `get`, `list` and `page` return it: its `data` parsed with
 * its type's schema, so checking `type` narrows `data`.
 */
export type NotificationOf<
  K extends NotificationTypes,
  F extends object = Record<never, never>,
> = {
  [N in TypeName<K>]: Rendered<N, StandardSchemaV1.InferOutput<K[N]>> & {
    readonly fields: RowFields<F>;
  };
}[TypeName<K>];

export interface NotificationsOptions<
  K extends NotificationTypes,
  H = undefined,
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  /**
   * `sqlTransport(postgres.asUser(claims))`, or over `postgres.admin` for the
   * service.
   */
  readonly transport: BlockTransport;
  /**
   * Each type's `data` schema. `send` validates against it, and `get`, `list`
   * and `page` parse stored data with it, so keep a schema able to read the
   * notifications already sent (or purge them). A stored value it rejects is a
   * `validation` error with the hint `NOTIFICATION_DATA_INVALID`; a type no
   * longer listed keeps its data as stored.
   */
  readonly types: K;
  /**
   * A Standard Schema for the events table's extra columns
   * (`blocks.notifications.options.extraColumns`): `send` validates them, and
   * `get`, `list` and `page` parse them.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the methods, such as a rule on `send`. */
  readonly hooks?: NoInfer<BlockHooks<Notifications<K, FieldsOf<S>>>>;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  /**
   * Loads what `render` needs for a whole page at once (actor names, subject
   * titles), so a list of 50 items costs one query instead of 50. Its result
   * reaches `render` as `context.hydrated`.
   */
  readonly hydrate?: (
    items: readonly NotificationItem[],
    context: { readonly locale?: string },
  ) => H | Promise<H>;
  /** Turns a notification into text at read time, in the reader's locale. */
  readonly render?: (
    item: NotificationItem,
    context: { readonly locale?: string; readonly hydrated?: H },
  ) => RenderedText;
  /** Types that wait for an action; `counts().actionable` counts them. */
  readonly actionable?: readonly TypeName<K>[];
  readonly avatars?: AvatarUrls;
  /** Senders for the non-`in_app` channels, used by `deliver()`. */
  readonly channels?: readonly NotificationChannel[];
  /**
   * Adds the `email` channel (`emailChannel`) over a
   * `DeliveryTransport<"email">`, such as `resendTransport`. Don't also list a
   * channel named `email`.
   */
  readonly email?: EmailChannelOptions;
  /**
   * Checks each claimed delivery's recipient before a channel sends it; a
   * recipient it leaves out is skipped, and a throw retries the deliveries
   * later. Defaults to `server.authorization.delivery.audience`; with
   * `server.authorization` but no such policy, to `subjectReaders(transport)`,
   * so a notification about a `config.subjects` record only reaches recipients
   * who may read it. In-app recipients are decided in SQL (`holdersOf`,
   * membership).
   */
  readonly audience?: SubscriberPolicy;
  /**
   * The `createServer` result, whose `authorization` hooks give the default
   * `audience`.
   */
  readonly server?: { readonly authorization?: AuthorizationHooks | undefined };
  /** Runs after a notification is stored, e.g. to call Next's `updateTag`. */
  readonly onSent?: (sent: {
    readonly id: string;
    readonly type: string;
    readonly tenant: string | null;
    readonly recipients: readonly string[];
  }) => void | Promise<void>;
  /** `betterSupabase.events`, for `notification.*` block events. */
  readonly events?: EventHub;
  readonly actorId?: string;
  readonly context?: RequestContext;
  /** Error mappers that run before the built-in ones. */
  readonly mappers?: readonly ErrorMapper[];
}

/**
 * The `notifications` SQL module as typed calls. `send` validates the data
 * against its type's schema; the database checks the send permission, leaves
 * out the actor and non-members and applies subscriptions and preferences.
 */
export interface Notifications<
  K extends NotificationTypes,
  F extends object = Record<never, never>,
> {
  /** The notification id, or `null` when nobody was left to notify. */
  send<N extends TypeName<K>>(
    type: N,
    input: SendInput<StandardSchemaV1.InferInput<K[N]>, F>,
  ): AsyncResult<SentNotification | null>;
  /**
   * Sends up to 1000 notifications in one `send_notifications` call, with
   * `send`'s checks per notification: one `Result` per item, in order, so a bad
   * one never drops the others. The outer result fails only when the call does.
   * Hooks on `send` don't run for these; hook `sendMany`.
   */
  sendMany(
    items: readonly SinkNotification<K, F>[],
  ): AsyncResult<readonly Result<SentNotification | null>[]>;
  get(
    id: string,
    options?: Pick<ListOptions, "locale" | "include">,
  ): AsyncResult<NotificationOf<K, F> | null>;
  list(
    options?: ListOptions<TypeName<K>>,
  ): AsyncResult<readonly NotificationOf<K, F>[]>;
  page(
    options?: PageOptions<TypeName<K>>,
  ): AsyncResult<NotificationPage<TypeName<K>, NotificationOf<K, F>>>;
  counts(options?: {
    readonly tenant?: string;
  }): AsyncResult<NotificationCounts>;
  /** Marks the given notifications, or all of them, read. */
  markRead(options?: {
    readonly ids?: readonly string[];
    readonly tenant?: string;
  }): AsyncResult<NotificationUpdate>;
  markUnread(options: {
    readonly ids: readonly string[];
    readonly tenant?: string;
  }): AsyncResult<NotificationUpdate>;
  dismiss(ids: readonly string[]): AsyncResult<NotificationUpdate>;
  /** Resolves every recipient's notification of a type about a subject. */
  resolve(input: {
    readonly type: TypeName<K>;
    readonly subject: NotificationSubject;
    readonly tenant?: string;
  }): AsyncResult<NotificationUpdate>;
  /** Sets the user's level for a subject; `null` removes it. */
  subscribe(input: {
    readonly subject: NotificationSubject;
    readonly level: SubscriptionLevel | null;
    readonly tenant?: string;
    /**
     * Another member; the service can set it, and with `ifAbsent` so can a
     * sender with the send permission in `tenant`.
     */
    readonly userId?: string;
    /**
     * Only add `level` when the member has no level for the subject, so an
     * auto-follow keeps their own `ignore` or `all`.
     */
    readonly ifAbsent?: boolean;
  }): AsyncResult<void>;
  subscriptions(options?: {
    readonly tenant?: string;
    readonly subject?: { readonly type: string; readonly id?: string };
  }): AsyncResult<readonly NotificationSubscription[]>;
  preferences(options?: {
    readonly tenant?: string;
  }): AsyncResult<readonly NotificationPreference[]>;
  /** Turns a type (`*` for all) on or off on a channel; `null` removes it. */
  setPreference(input: {
    readonly type: TypeName<K> | "*";
    readonly channel: string;
    readonly enabled: boolean | null;
    /** One organization, or everywhere when omitted. */
    readonly tenant?: string;
  }): AsyncResult<void>;
  /** Sends pending deliveries through `channels`. Run it from a cron or a job. */
  deliver(options?: DeliverOptions): Promise<DeliverResult>;
  /**
   * Deletes up to `batch` (10,000) notifications older than `olderThan` (`90
   * days`) with their recipients and deliveries. Service only.
   */
  purge(olderThan?: string, batch?: number): AsyncResult<number>;
  /**
   * Stops `channel` from sending to an address; `deliver()` skips its
   * deliveries. `true` when the address was not suppressed yet. Service only;
   * `resendWebhook` calls it for bounces and complaints.
   */
  suppress(input: SuppressInput): AsyncResult<boolean>;
  /** Lifts a suppression. `true` when there was one. Service only. */
  unsuppress(address: string, channel?: string): AsyncResult<boolean>;
  /** The caller's own suppressions, newest first (every row for the service). */
  suppressions(options?: {
    readonly limit?: number;
  }): AsyncResult<readonly NotificationSuppression[]>;
  /**
   * Records what a provider reported about a sent message: stores it on the
   * delivery once per `providerEventId`, moves the delivery's provider status
   * forward, suppresses the address on a bounce or a complaint, and emits
   * `notification.<kind>` with the notification's subject. `null` when no
   * delivery has that provider message id. Service only; `resendWebhook` calls
   * it for every status.
   */
  recordDeliveryEvent(
    input: DeliveryEventInput,
  ): AsyncResult<RecordedDeliveryEvent | null>;
  /**
   * The deliveries of the notifications about one record, newest first, each
   * with its provider events: a record's sent emails. The service reads every
   * tenant; a member needs the send permission in `tenant`.
   */
  subjectDeliveries(options: {
    readonly subject: { readonly type: string; readonly id: string };
    readonly tenant?: string;
    /** Up to 200. Defaults to 50. */
    readonly limit?: number;
  }): AsyncResult<readonly SubjectDelivery[]>;
  /**
   * An `EventSink` that sends a notification for each event `map` returns one
   * for. The key defaults to the event id and the tenant to its `partitionkey`,
   * so a redelivered event sends nothing new. A failed send rejects, so the
   * forwarder retries. The comments module already notifies
   * `comment.mentioned`; don't map it again.
   */
  sink(options: NotificationSinkOptions<K>): EventSink;
}

/** A notification for `sink`, with its type next to the `send` input. */
export type SinkNotification<
  K extends NotificationTypes,
  F extends object = Record<never, never>,
> = {
  [N in TypeName<K>]: { readonly type: N } & SendInput<
    StandardSchemaV1.InferInput<K[N]>,
    F
  >;
}[TypeName<K>];

export interface NotificationSinkOptions<K extends NotificationTypes> {
  /**
   * The notification for an event, or `null` to skip it. `event.type` has no
   * `typePrefix`.
   */
  map(
    event: CloudEvent,
  ): SinkNotification<K> | null | Promise<SinkNotification<K> | null>;
  /**
   * Stripped from each event type before `map`. Defaults to
   * `dev.better-supabase.`.
   */
  readonly typePrefix?: string;
}
