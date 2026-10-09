import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { NotificationEventData } from "../../core/block-events.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { EventHub } from "../../core/events.ts";
import type { RequestContext } from "../../core/plugin.ts";
import type { NotificationChannel, NotificationMessage } from "./channel.ts";
import type {
  NotificationItem,
  NotificationSubject,
  RenderedText,
} from "./types.ts";

import { emitBlockEvent } from "../../core/block-events.ts";
import { rawError } from "../../core/block-transport.ts";
import { dbError, mapDbError } from "../../core/errors.ts";
import { AsyncResult, err, ok, toDbError } from "../../core/result.ts";
import { validate } from "../../core/standard.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  DEFAULT_BLOCK_SCHEMA,
  errorText,
  isRecord,
  mappersOf,
  optionalInstant,
  optionalText,
} from "../shared.ts";

/** Notification type to the Standard Schema of its `data`. */
export type NotificationTypes = Readonly<Record<string, StandardSchemaV1>>;

type TypeName<K extends NotificationTypes> = keyof K & string;

export interface SendInput<D = unknown> {
  /** Who gets it. Watchers of `subject` and the `notification_audience` hook add more. */
  readonly recipients?: readonly string[];
  /** The organization; required when an authenticated user sends. */
  readonly tenant?: string;
  readonly subject?: NotificationSubject;
  readonly summary?: string;
  readonly actionPath?: string;
  /** One of `sql.modules.notifications.options.priorities`. Defaults to `normal`. */
  readonly priority?: string;
  readonly data: D;
  /** With a key, sending again (per tenant) returns the first notification. */
  readonly key?: string;
  /** Defaults to `sql.modules.notifications.options.channels`. */
  readonly channels?: readonly string[];
  /** Also notify the user who caused it. Defaults to `false`. */
  readonly includeActor?: boolean;
  /**
   * `participating` (default) reaches subject watchers at both levels;
   * `all` is routine activity that only `all` watchers get.
   */
  readonly activity?: "participating" | "all";
  /** Create it already resolved, e.g. for a record of a finished approval. */
  readonly resolved?: boolean;
  /** The actor, when the service sends on a user's behalf. */
  readonly actorId?: string;
  /**
   * Add the watchers of `subject`. Defaults to `true`; `false` reaches only
   * `recipients` and the audience hook (members ignoring the subject stay
   * out either way).
   */
  readonly watchers?: boolean;
  /** Users left out after the watchers and the audience hook are added. */
  readonly exclude?: readonly string[];
}

export interface ListOptions<K extends string = string> {
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
  readonly before?:
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
  "before"
> {
  readonly offset?: number;
}

export interface NotificationPage<K extends string = string> {
  readonly items: readonly Rendered<K>[];
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
  readonly skipped: number;
  /** Deliveries that threw; retried later unless they ran out of attempts. */
  readonly failed: number;
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

export interface NotificationsOptions<
  K extends NotificationTypes,
  H = undefined,
> extends BlockTemporalOptions {
  /** `sqlTransport(postgres.asUser(claims))`, or over `postgres.admin` for the service. */
  readonly transport: BlockTransport;
  /** Each type's `data` schema: `send` validates against it. */
  readonly types: K;
  /** `sql.modules.notifications.schema`. Defaults to `better_supabase`. */
  readonly schema?: string;
  /**
   * Loads what `render` needs for a whole page at once (actor names,
   * subject titles), so a list of 50 items costs one query instead of 50.
   * Its result reaches `render` as `context.hydrated`.
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
  /** @deprecated Use `mappers`. Removed in 0.8. */
  readonly errorMappers?: readonly ErrorMapper[];
}

/**
 * The `notifications` SQL module as typed calls. `send` validates the
 * data against its type's schema; the database checks the send permission,
 * leaves out the actor and non-members and applies subscriptions and
 * preferences.
 */
export interface Notifications<K extends NotificationTypes> {
  /** The notification id, or `null` when nobody was left to notify. */
  send<N extends TypeName<K>>(
    type: N,
    input: SendInput<StandardSchemaV1.InferInput<K[N]>>,
  ): AsyncResult<SentNotification | null>;
  get(
    id: string,
    options?: Pick<ListOptions, "locale" | "include">,
  ): AsyncResult<Rendered<TypeName<K>> | null>;
  list(
    options?: ListOptions<TypeName<K>>,
  ): AsyncResult<readonly Rendered<TypeName<K>>[]>;
  page(
    options?: PageOptions<TypeName<K>>,
  ): AsyncResult<NotificationPage<TypeName<K>>>;
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
   * Deletes up to `batch` (10,000) notifications older than `olderThan`
   * (`90 days`) with their recipients and deliveries. Service only.
   */
  purge(olderThan?: string, batch?: number): AsyncResult<number>;
}

const nullableText = (value: unknown): string | null =>
  optionalText(value) ?? null;

const nullableInstant = (value: unknown): Temporal.Instant | null =>
  optionalInstant(value) ?? null;

function toItem(row: Record<string, unknown>): NotificationItem {
  const type = nullableText(row["subject_type"]);
  const id = nullableText(row["subject_id"]);
  const label = nullableText(row["subject_label"]);
  return {
    id: String(row["id"]),
    eventId: String(row["event_id"]),
    type: String(row["type"]),
    data: row["data"] ?? {},
    tenant: nullableText(row["tenant"]),
    actorId: nullableText(row["actor_id"]),
    subject:
      type === null || id === null
        ? null
        : { type, id, ...(label === null ? {} : { label }) },
    summary: nullableText(row["summary"]),
    actionPath: nullableText(row["action_path"]),
    priority: nullableText(row["priority"]),
    createdAt: nullableInstant(row["created_at"]) ?? temporal().Now.instant(),
    readAt: nullableInstant(row["read_at"]),
    resolvedAt: nullableInstant(row["resolved_at"]),
  };
}

function cursorOf(before: ListOptions["before"]): {
  readonly before: string | null;
  readonly before_id: string | null;
} {
  if (before === undefined) return { before: null, before_id: null };
  if ("epochNanoseconds" in before) {
    return { before: before.toString(), before_id: null };
  }
  return { before: before.createdAt.toString(), before_id: before.id };
}

function publicObjectUrl(url: string, bucket: string, path: string): string {
  const object = path
    .replace(/^\/+/, "")
    .split("/")
    .map(encodeURIComponent)
    .join("/");
  return `${url.replace(/\/+$/, "")}/storage/v1/object/public/${encodeURIComponent(bucket)}/${object}`;
}

function filtersOf(filters: PageOptions): Record<string, unknown> {
  return {
    tenant: filters.tenant ?? null,
    status: filters.status ?? "all",
    read: filters.read ?? null,
    resolved: filters.resolved ?? null,
    dismissed: filters.dismissed === undefined ? false : filters.dismissed,
    types: filters.types ?? null,
    subject_types: filters.subjectTypes ?? null,
    search: filters.search ?? null,
  };
}

const LEVELS: readonly SubscriptionLevel[] = ["participating", "all", "ignore"];

export function createNotifications<
  const K extends NotificationTypes,
  H = undefined,
>(options: NotificationsOptions<K, H>): Notifications<K> {
  applyTemporal(options);
  const { transport } = options;
  const schema = options.schema ?? DEFAULT_BLOCK_SCHEMA;
  const mappers = mappersOf(options);
  const run = blockCall(transport, schema, mappers);

  const call = async (
    fn: string,
    args: Readonly<Record<string, unknown>>,
  ): Promise<unknown> => transport.call(schema, fn, args);

  function emit(
    type:
      | "notification.created"
      | "notification.delivered"
      | "notification.failed",
    data: NotificationEventData,
    tenant: string | null,
  ): void {
    if (!options.events) return;
    emitBlockEvent(options.events, type, data, {
      subject: `notifications/${data.notificationId}`,
      ...(tenant ? { tenant } : {}),
      ...(options.actorId ? { actorId: options.actorId } : {}),
      ...(options.context ? { context: options.context } : {}),
    });
  }

  const render = (
    item: NotificationItem,
    locale?: string,
    hydrated?: H,
  ): Rendered => {
    if (!options.render) return item;
    return {
      ...item,
      text: options.render(item, {
        ...(locale === undefined ? {} : { locale }),
        ...(hydrated === undefined ? {} : { hydrated }),
      }),
    };
  };

  const withAvatarUrl = (actor: NotificationActor): NotificationActor => {
    const avatars = options.avatars;
    const path = actor.avatarPath;
    if (!avatars || typeof path !== "string" || path === "") return actor;
    return {
      ...actor,
      avatarUrl:
        typeof avatars === "function"
          ? avatars(path)
          : publicObjectUrl(avatars.url, avatars.bucket, path),
    };
  };

  const actorsOf = async (
    items: readonly NotificationItem[],
  ): Promise<ReadonlyMap<string, NotificationActor>> => {
    const ids = [
      ...new Set(items.flatMap((item) => (item.actorId ? [item.actorId] : []))),
    ];
    if (ids.length === 0) return new Map();
    const value = await call("notification_actors", { ids });
    return new Map(
      Object.entries(isRecord(value) ? value : {}).flatMap(([id, profile]) =>
        isRecord(profile) ? [[id, withAvatarUrl({ ...profile, id })]] : [],
      ),
    );
  };

  const itemsOf = (value: unknown): NotificationItem[] =>
    (Array.isArray(value) ? value : []).filter(isRecord).map(toItem);

  const updateOf = (value: unknown): NotificationUpdate => ({
    count: Number(isRecord(value) ? (value["count"] ?? 0) : 0),
    items: itemsOf(isRecord(value) ? value["items"] : []),
  });

  const decorate = (
    items: readonly NotificationItem[],
    listOptions: Pick<ListOptions, "locale" | "include">,
  ): AsyncResult<readonly Rendered[]> =>
    AsyncResult.from(async () => {
      try {
        const locale = listOptions.locale;
        const context = locale === undefined ? {} : { locale };
        const [hydrated, actors] = await Promise.all([
          options.hydrate ? options.hydrate(items, context) : undefined,
          listOptions.include?.includes("actor") ? actorsOf(items) : undefined,
        ]);
        return ok(
          items.map((item) => {
            const rendered = render(item, locale, hydrated);
            return actors
              ? {
                  ...rendered,
                  actor: item.actorId
                    ? (actors.get(item.actorId) ?? null)
                    : null,
                }
              : rendered;
          }),
        );
      } catch (cause) {
        const raw = rawError(cause);
        return err(raw ? mapDbError(raw, mappers) : toDbError(cause));
      }
    });

  async function deliverOne(
    channel: NotificationChannel,
    row: Record<string, unknown>,
    maxAttempts: number,
  ): Promise<"sent" | "skipped" | "failed"> {
    const notification = isRecord(row["notification"])
      ? toItem(row["notification"])
      : undefined;
    if (!notification) throw new TypeError("claim returned no notification");
    const attempts = Number(row["attempts"] ?? 1);
    const message: NotificationMessage = {
      deliveryId: String(row["delivery_id"]),
      channel: channel.name,
      attempts,
      userId: String(row["user_id"]),
      email: nullableText(row["email"]),
      notification,
      ...(options.render ? { text: options.render(notification, {}) } : {}),
    };
    try {
      const result = await channel.send(message);
      const status = result?.status ?? "sent";
      await call("complete_notification_delivery", {
        delivery: message.deliveryId,
        status,
        provider: result?.provider ?? null,
        provider_message_id: result?.providerMessageId ?? null,
      });
      if (status === "sent") {
        emit(
          "notification.delivered",
          {
            notificationId: notification.eventId,
            type: notification.type,
            channel: channel.name,
          },
          notification.tenant,
        );
      }
      return status;
    } catch (cause) {
      const error = errorText(cause);
      await call("complete_notification_delivery", {
        delivery: message.deliveryId,
        status: "pending",
        error,
        max_attempts: maxAttempts,
      });
      emit(
        "notification.failed",
        {
          notificationId: notification.eventId,
          type: notification.type,
          channel: channel.name,
          error,
        },
        notification.tenant,
      );
      return "failed";
    }
  }

  return {
    send(type, input) {
      return AsyncResult.from(async () => {
        const schemaOf = Object.hasOwn(options.types, type)
          ? options.types[type]
          : undefined;
        if (schemaOf === undefined) {
          return err(
            dbError("validation", `Unknown notification type "${type}"`, {
              issues: [{ path: ["type"], message: `Unknown type "${type}"` }],
              hint: "NOTIFICATION_TYPE_UNKNOWN",
            }),
          );
        }
        const data = await validate(schemaOf, input.data, `${type} data`);
        if (!data.ok) return err(data.error);
        const notification = {
          type,
          data: data.data,
          recipients: input.recipients ?? [],
          tenant: input.tenant,
          subject_type: input.subject?.type,
          subject_id: input.subject?.id,
          subject_label: input.subject?.label,
          summary: input.summary,
          action_path: input.actionPath,
          priority: input.priority,
          key: input.key,
          channels: input.channels,
          include_actor: input.includeActor,
          activity: input.activity,
          resolved: input.resolved,
          actor: input.actorId,
          watchers: input.watchers,
          exclude: input.exclude,
        };
        const sent = await run(
          "send_notification",
          { notification },
          (value): SentNotification | null =>
            isRecord(value) && value["id"] !== null && value["id"] !== undefined
              ? {
                  id: String(value["id"]),
                  recipients: (Array.isArray(value["recipients"])
                    ? value["recipients"]
                    : []
                  ).map(String),
                }
              : null,
        );
        if (!sent.ok || sent.data === null) return sent;
        const { id, recipients } = sent.data;
        emit(
          "notification.created",
          { notificationId: id, type, recipientIds: recipients },
          input.tenant ?? null,
        );
        if (options.onSent) {
          try {
            await options.onSent({
              id,
              type,
              tenant: input.tenant ?? null,
              recipients,
            });
          } catch (cause) {
            return err(toDbError(cause));
          }
        }
        return sent;
      });
    },
    get(id, getOptions = {}) {
      return run("get_notification", { id }, (value) =>
        isRecord(value) ? toItem(value) : null,
      ).andThen((item) =>
        item === null
          ? AsyncResult.ok(null)
          : decorate([item], getOptions).map((items) => items[0] ?? null),
      );
    },
    list(listOptions = {}) {
      return run(
        "list_notifications",
        {
          ...filtersOf(listOptions),
          ...cursorOf(listOptions.before),
          max_items: listOptions.limit ?? 50,
        },
        itemsOf,
      ).andThen((items) => decorate(items, listOptions));
    },
    page(pageOptions = {}) {
      return run(
        "notification_page",
        {
          ...filtersOf(pageOptions),
          max_items: pageOptions.limit ?? 50,
          skip: pageOptions.offset ?? 0,
        },
        (value) => ({
          items: itemsOf(isRecord(value) ? value["items"] : []),
          total: Number(isRecord(value) ? (value["total"] ?? 0) : 0),
        }),
      ).andThen((found) =>
        decorate(found.items, pageOptions).map((items) => ({
          items,
          total: found.total,
        })),
      );
    },
    counts(countOptions = {}) {
      return run(
        "notification_counts",
        {
          tenant: countOptions.tenant ?? null,
          actionable: options.actionable ?? [],
        },
        (value) => ({
          unread: Number(isRecord(value) ? (value["unread"] ?? 0) : 0),
          actionable: Number(isRecord(value) ? (value["actionable"] ?? 0) : 0),
          actionableSubjects: Number(
            isRecord(value) ? (value["actionable_subjects"] ?? 0) : 0,
          ),
        }),
      );
    },
    markRead(readOptions = {}) {
      return run(
        "mark_notifications_read",
        { ids: readOptions.ids ?? null, tenant: readOptions.tenant ?? null },
        updateOf,
      );
    },
    markUnread(unreadOptions) {
      return run(
        "mark_notifications_unread",
        { ids: unreadOptions.ids, tenant: unreadOptions.tenant ?? null },
        updateOf,
      );
    },
    dismiss(ids) {
      return run("dismiss_notifications", { ids }, updateOf);
    },
    resolve(input) {
      return run(
        "resolve_notifications",
        {
          type: input.type,
          subject_type: input.subject.type,
          subject_id: input.subject.id,
          tenant: input.tenant ?? null,
        },
        updateOf,
      );
    },
    subscribe(input) {
      return run(
        "set_notification_subscription",
        {
          subject_type: input.subject.type,
          subject_id: input.subject.id,
          level: input.level,
          tenant: input.tenant ?? null,
          member: input.userId ?? null,
          if_absent: input.ifAbsent,
        },
        () => undefined,
      );
    },
    subscriptions(subscriptionOptions = {}) {
      return run(
        "list_notification_subscriptions",
        {
          tenant: subscriptionOptions.tenant ?? null,
          subject_type: subscriptionOptions.subject?.type ?? null,
          subject_id: subscriptionOptions.subject?.id ?? null,
        },
        (value) =>
          (Array.isArray(value) ? value : [])
            .filter(isRecord)
            .flatMap((row): NotificationSubscription[] => {
              const level = LEVELS.find((entry) => entry === row["level"]);
              return level === undefined
                ? []
                : [
                    {
                      subject: {
                        type: String(row["subject_type"]),
                        id: String(row["subject_id"]),
                      },
                      level,
                      tenant: nullableText(row["tenant"]),
                      createdAt: nullableInstant(row["created_at"]),
                    },
                  ];
            }),
      );
    },
    preferences(preferenceOptions = {}) {
      return run(
        "list_notification_preferences",
        { tenant: preferenceOptions.tenant ?? null },
        (value) =>
          (Array.isArray(value) ? value : [])
            .filter(isRecord)
            .map((row): NotificationPreference => ({
              type: String(row["type"]),
              channel: String(row["channel"]),
              enabled: row["enabled"] === true,
              tenant: nullableText(row["tenant"]),
            })),
      );
    },
    setPreference(input) {
      return run(
        "set_notification_preference",
        {
          type: input.type,
          channel: input.channel,
          enabled: input.enabled,
          tenant: input.tenant ?? null,
        },
        () => undefined,
      );
    },
    async deliver(deliverOptions = {}) {
      const wanted = deliverOptions.channels;
      const channels = (options.channels ?? []).filter(
        (channel) => !wanted || wanted.includes(channel.name),
      );
      const deadline =
        deliverOptions.budgetMs === undefined
          ? Number.POSITIVE_INFINITY
          : Date.now() + deliverOptions.budgetMs;
      const batch = deliverOptions.batch ?? 50;
      const counts = { sent: 0, skipped: 0, failed: 0 };
      // Channels are independent, so a slow provider doesn't hold up the
      // others; each channel's deliveries go out in order.
      await Promise.all(
        channels.map(async (channel) => {
          while (Date.now() < deadline) {
            const claimed = await call("claim_notification_deliveries", {
              channel: channel.name,
              max_items: batch,
              lease: deliverOptions.lease ?? "5 minutes",
              max_attempts: deliverOptions.maxAttempts ?? 5,
            });
            const rows = (Array.isArray(claimed) ? claimed : []).filter(
              isRecord,
            );
            for (const row of rows) {
              counts[
                await deliverOne(channel, row, deliverOptions.maxAttempts ?? 5)
              ] += 1;
            }
            if (rows.length < batch) break;
          }
        }),
      );
      return counts;
    },
    purge(olderThan, batch) {
      return run(
        "purge_notifications",
        { older_than: olderThan ?? null, batch: batch ?? null },
        Number,
      );
    },
  };
}
