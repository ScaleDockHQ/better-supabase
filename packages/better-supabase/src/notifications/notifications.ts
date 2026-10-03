import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { ErrorMapper } from "../core/errors.ts";
import type { EventHub } from "../core/events.ts";
import type { NotificationEventData } from "../core/kit-events.ts";
import type { KitTransport } from "../core/kit-transport.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { NotificationChannel, NotificationMessage } from "./channel.ts";
import type {
  NotificationItem,
  NotificationSubject,
  RenderedText,
} from "./types.ts";

import { dbError, mapDbError } from "../core/errors.ts";
import { emitKitEvent } from "../core/kit-events.ts";
import { rawError } from "../core/kit-transport.ts";
import { AsyncResult, err, ok, toDbError } from "../core/result.ts";
import { validate } from "../core/standard.ts";
import { temporal } from "../core/temporal-required.ts";

/** Kind name to the Standard Schema of its `data`. */
export type NotificationKinds = Readonly<Record<string, StandardSchemaV1>>;

type KindName<K extends NotificationKinds> = keyof K & string;

export interface SendInput<D = unknown> {
  /** Who gets it. Watchers of `subject` and the `notification_audience` hook add more. */
  readonly recipients?: readonly string[];
  /** The organization; required when an authenticated user sends. */
  readonly tenant?: string;
  readonly subject?: NotificationSubject;
  readonly summary?: string;
  readonly actionPath?: string;
  /** One of `kits.notifications.options.priorities`. Defaults to `normal`. */
  readonly priority?: string;
  readonly data: D;
  /** With a key, sending again (per tenant) returns the first notification. */
  readonly key?: string;
  /** Defaults to `kits.notifications.options.channels`. */
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
}

export interface ListOptions<K extends string = string> {
  readonly tenant?: string;
  readonly status?: "all" | "unread" | "read" | "unresolved";
  readonly kinds?: readonly K[];
  /** Page: only notifications created before this. */
  readonly before?: Temporal.Instant;
  /** Up to 200. Defaults to 50. */
  readonly limit?: number;
  /** Passed to `render`. */
  readonly locale?: string;
}

export interface NotificationCounts {
  readonly unread: number;
  /** Unresolved notifications of the `actionable` kinds. */
  readonly actionable: number;
}

export type SubscriptionLevel = "participating" | "all" | "ignore";

export interface DeliverOptions {
  /** Channel names to work on. Defaults to every channel in `channels`. */
  readonly channels?: readonly string[];
  /** Deliveries per claim. Defaults to 50. */
  readonly batch?: number;
  /** How long a claimed delivery waits before another worker retries it. */
  readonly lease?: string;
  /** Tries before a delivery is `failed`. Defaults to 5. */
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
}

export interface NotificationsOptions<K extends NotificationKinds> {
  /** `sqlTransport(postgres.asUser(claims))`, or over `postgres.admin` for the service. */
  readonly transport: KitTransport;
  /** Each kind's `data` schema: `send` validates against it. */
  readonly kinds: K;
  /** `kits.notifications.schema`. Defaults to `better_supabase`. */
  readonly schema?: string;
  /** Turns a notification into text at read time, in the reader's locale. */
  readonly render?: (
    item: NotificationItem,
    context: { readonly locale?: string },
  ) => RenderedText;
  /** Kinds that wait for an action; `counts().actionable` counts them. */
  readonly actionable?: readonly KindName<K>[];
  /** Senders for the non-`in_app` channels, used by `deliver()`. */
  readonly channels?: readonly NotificationChannel[];
  /** Runs after a notification is stored, e.g. to call Next's `updateTag`. */
  readonly onSent?: (sent: {
    readonly id: string;
    readonly kind: string;
    readonly tenant: string | null;
    readonly recipients: readonly string[];
  }) => void | Promise<void>;
  /** `betterSupabase.events`, for `notification.*` kit events. */
  readonly events?: EventHub;
  readonly actorId?: string;
  readonly context?: RequestContext;
  readonly errorMappers?: readonly ErrorMapper[];
}

/**
 * The `notifications` SQL kit module as typed calls. `send` validates the
 * data against its kind's schema; the database checks the send permission,
 * leaves out the actor and non-members and applies subscriptions and
 * preferences.
 */
export interface Notifications<K extends NotificationKinds> {
  /** The notification id, or `null` when nobody was left to notify. */
  send<N extends KindName<K>>(
    kind: N,
    input: SendInput<StandardSchemaV1.InferInput<K[N]>>,
  ): AsyncResult<string | null>;
  list(
    options?: ListOptions<KindName<K>>,
  ): AsyncResult<readonly Rendered<KindName<K>>[]>;
  counts(options?: {
    readonly tenant?: string;
  }): AsyncResult<NotificationCounts>;
  /** Marks the given notifications, or all of them, read. */
  markRead(options?: {
    readonly ids?: readonly string[];
    readonly tenant?: string;
  }): AsyncResult<number>;
  dismiss(ids: readonly string[]): AsyncResult<number>;
  /** Resolves every recipient's notification of a kind about a subject. */
  resolve(input: {
    readonly kind: KindName<K>;
    readonly subject: NotificationSubject;
    readonly tenant?: string;
  }): AsyncResult<number>;
  /** Sets the user's level for a subject; `null` removes it. */
  subscribe(input: {
    readonly subject: NotificationSubject;
    readonly level: SubscriptionLevel | null;
    readonly tenant?: string;
    /** Another member; only the service can set it. */
    readonly userId?: string;
  }): AsyncResult<void>;
  /** Turns a kind (`*` for all) on or off on a channel; `null` removes it. */
  setPreference(input: {
    readonly kind: KindName<K> | "*";
    readonly channel: string;
    readonly enabled: boolean | null;
    /** One organization, or everywhere when omitted. */
    readonly tenant?: string;
  }): AsyncResult<void>;
  /** Sends pending deliveries through `channels`. Run it from a cron or a job. */
  deliver(options?: DeliverOptions): Promise<DeliverResult>;
}

const DEFAULT_SCHEMA = "better_supabase";

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const textOf = (value: unknown): string | null =>
  value === null || value === undefined ? null : String(value);

const instantOf = (value: unknown): Temporal.Instant | null =>
  typeof value === "string" ? temporal().Instant.from(value) : null;

function toItem(row: Record<string, unknown>): NotificationItem {
  const type = textOf(row["subject_type"]);
  const id = textOf(row["subject_id"]);
  const label = textOf(row["subject_label"]);
  return {
    id: String(row["id"]),
    eventId: String(row["event_id"]),
    kind: String(row["kind"]),
    data: row["data"] ?? {},
    tenant: textOf(row["tenant"]),
    actorId: textOf(row["actor_id"]),
    subject:
      type === null || id === null
        ? null
        : { type, id, ...(label === null ? {} : { label }) },
    summary: textOf(row["summary"]),
    actionPath: textOf(row["action_path"]),
    priority: textOf(row["priority"]),
    createdAt: instantOf(row["created_at"]) ?? temporal().Now.instant(),
    readAt: instantOf(row["read_at"]),
    resolvedAt: instantOf(row["resolved_at"]),
  };
}

const errorText = (cause: unknown): string =>
  cause instanceof Error ? cause.message : String(cause);

export function createNotifications<const K extends NotificationKinds>(
  options: NotificationsOptions<K>,
): Notifications<K> {
  const { transport } = options;
  const schema = options.schema ?? DEFAULT_SCHEMA;
  const mappers = options.errorMappers ?? [];

  const call = async (
    fn: string,
    args: Readonly<Record<string, unknown>>,
  ): Promise<unknown> => transport.call(schema, fn, args);

  function run<T>(
    fn: string,
    args: Readonly<Record<string, unknown>>,
    then: (value: unknown) => T | Promise<T>,
  ): AsyncResult<T> {
    return AsyncResult.from(async () => {
      let value: unknown;
      try {
        value = await call(fn, args);
      } catch (cause) {
        const raw = rawError(cause);
        return err(raw ? mapDbError(raw, mappers) : toDbError(cause));
      }
      return ok(await then(value));
    });
  }

  function emit(
    type:
      | "notification.created"
      | "notification.delivered"
      | "notification.failed",
    data: NotificationEventData,
    tenant: string | null,
  ): void {
    if (!options.events) return;
    emitKitEvent(options.events, type, data, {
      subject: `notifications/${data.notificationId}`,
      ...(tenant ? { tenant } : {}),
      ...(options.actorId ? { actorId: options.actorId } : {}),
      ...(options.context ? { context: options.context } : {}),
    });
  }

  const render = (item: NotificationItem, locale?: string): Rendered => {
    if (!options.render) return item;
    return {
      ...item,
      text: options.render(item, locale === undefined ? {} : { locale }),
    };
  };

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
      email: textOf(row["email"]),
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
            kind: notification.kind,
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
        status: attempts >= maxAttempts ? "failed" : "pending",
        error,
      });
      emit(
        "notification.failed",
        {
          notificationId: notification.eventId,
          kind: notification.kind,
          channel: channel.name,
          error,
        },
        notification.tenant,
      );
      return "failed";
    }
  }

  return {
    send(kind, input) {
      return AsyncResult.from(async () => {
        const schemaOf = Object.hasOwn(options.kinds, kind)
          ? options.kinds[kind]
          : undefined;
        if (schemaOf === undefined) {
          return err(
            dbError("validation", `Unknown notification kind "${kind}"`, {
              issues: [{ path: ["kind"], message: `Unknown kind "${kind}"` }],
              hint: "NOTIFICATION_KIND_UNKNOWN",
            }),
          );
        }
        const data = await validate(schemaOf, input.data, `${kind} data`);
        if (!data.ok) return err(data.error);
        const notification = {
          kind,
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
        };
        const sent = await run("notify", { notification }, (value) =>
          value === null ? null : String(value),
        );
        if (!sent.ok || sent.data === null) return sent;
        const recipients = input.recipients ?? [];
        emit(
          "notification.created",
          { notificationId: sent.data, kind, recipientIds: recipients },
          input.tenant ?? null,
        );
        if (options.onSent) {
          try {
            await options.onSent({
              id: sent.data,
              kind,
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
    list(listOptions = {}) {
      return run(
        "list_notifications",
        {
          tenant: listOptions.tenant ?? null,
          status: listOptions.status ?? "all",
          kinds: listOptions.kinds ?? null,
          before: listOptions.before?.toString() ?? null,
          max_items: listOptions.limit ?? 50,
        },
        (value) =>
          (Array.isArray(value) ? value : [])
            .filter(isRecord)
            .map((row) => render(toItem(row), listOptions.locale)),
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
        }),
      );
    },
    markRead(readOptions = {}) {
      return run(
        "mark_notifications_read",
        { ids: readOptions.ids ?? null, tenant: readOptions.tenant ?? null },
        Number,
      );
    },
    dismiss(ids) {
      return run("dismiss_notifications", { ids }, Number);
    },
    resolve(input) {
      return run(
        "resolve_notifications",
        {
          kind: input.kind,
          subject_type: input.subject.type,
          subject_id: input.subject.id,
          tenant: input.tenant ?? null,
        },
        Number,
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
        },
        () => undefined,
      );
    },
    setPreference(input) {
      return run(
        "set_notification_preference",
        {
          kind: input.kind,
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
      for (const channel of channels) {
        while (Date.now() < deadline) {
          const claimed = await call("claim_notification_deliveries", {
            channel: channel.name,
            max_items: batch,
            lease: deliverOptions.lease ?? "5 minutes",
          });
          const rows = (Array.isArray(claimed) ? claimed : []).filter(isRecord);
          for (const row of rows) {
            counts[
              await deliverOne(channel, row, deliverOptions.maxAttempts ?? 5)
            ] += 1;
          }
          if (rows.length < batch) break;
        }
      }
      return counts;
    },
  };
}
