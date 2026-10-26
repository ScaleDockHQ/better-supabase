import type { StandardSchemaV1 } from "@standard-schema/spec";

import type {
  BlockFields,
  FieldsOf,
  RowFields,
} from "../../core/block-fields.ts";
import type { Result } from "../../core/result.ts";
import type {
  DeliveryEventKind,
  ListOptions,
  NotificationActor,
  NotificationOf,
  NotificationPreference,
  NotificationSubscription,
  NotificationSuppression,
  NotificationTypes,
  NotificationUpdate,
  Notifications,
  NotificationsOptions,
  Rendered,
  SendInput,
  SentNotification,
  SinkNotification,
  SubjectDelivery,
  SuppressionReason,
} from "./api-types.ts";
import type { NotificationChannel, NotificationMessage } from "./channel.ts";
import type { Claimed, Hydration } from "./delivery-batch.ts";
import type { NotificationsEvents } from "./events.ts";
import type { NotificationItem } from "./types.ts";

import { MAX_BATCH } from "../../core/batch-limit.ts";
import { blockEmitter } from "../../core/block-events.ts";
import { blockFields } from "../../core/block-fields.ts";
import {
  batchResultsOf,
  budget,
  chunksOf,
  toBlockError,
} from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { DbException, dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok, toDbError } from "../../core/result.ts";
import { validate } from "../../core/standard.ts";
import { subjectReaders } from "../../core/subject-readers.ts";
import { stripTypePrefix } from "../../events/cloud-event.ts";
import { allowedSubscribers } from "../../realtime/subscribers.ts";
import {
  DEFAULT_BLOCK_SCHEMA,
  applyTemporal,
  blockCall,
  errorText,
  isRecord,
  pageOf,
  nullableInstant,
  nullableText,
} from "../shared.ts";
import {
  byLocale,
  deliveryChannels,
  deliveryData,
  subscriberEventOf,
} from "./delivery-batch.ts";
import {
  deliveryEventKindOf,
  emitDeliveryEvent,
  recordedDeliveryEventOf,
} from "./delivery-events.ts";
import {
  LEVELS,
  cursorOf,
  filtersOf,
  publicObjectUrl,
  toItem,
} from "./rows.ts";

const SUPPRESSION_REASONS: readonly SuppressionReason[] = [
  "bounce",
  "complaint",
  "manual",
];

const DELIVERY_STATUSES: readonly SubjectDelivery["status"][] = [
  "pending",
  "sent",
  "failed",
  "skipped",
];

const subjectDeliveryOf = (row: Record<string, unknown>): SubjectDelivery => ({
  id: String(row["id"]),
  notificationId: String(row["notification_id"]),
  type: String(row["type"]),
  channel: String(row["channel"]),
  userId: String(row["user_id"]),
  status:
    DELIVERY_STATUSES.find((status) => status === row["status"]) ?? "pending",
  provider: nullableText(row["provider"]),
  providerMessageId: nullableText(row["provider_message_id"]),
  providerStatus: deliveryEventKindOf(row["provider_status"]),
  providerStatusAt: nullableInstant(row["provider_status_at"]),
  templateKey: nullableText(row["template_key"]),
  error: nullableText(row["error"]),
  attempts: typeof row["attempts"] === "number" ? row["attempts"] : null,
  createdAt: nullableInstant(row["created_at"]),
  deliveredAt: nullableInstant(row["delivered_at"]),
  events: (Array.isArray(row["events"]) ? row["events"] : [])
    .filter(isRecord)
    .flatMap((event) => {
      const kind = deliveryEventKindOf(event["kind"]);

      return kind === null
        ? []
        : [
            {
              kind,
              occurredAt: nullableInstant(event["occurred_at"]),
              detail: isRecord(event["detail"]) ? event["detail"] : {},
            },
          ];
    }),
});

export function createNotifications<
  const K extends NotificationTypes,
  H = undefined,
  S extends StandardSchemaV1 | undefined = undefined,
>(options: NotificationsOptions<K, H, S>): Notifications<K, FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "notification fields",
  );

  /** An item with its data and fields parsed. */
  type ParsedItem = NotificationItem & { readonly fields: RowFields<F> };

  const { transport } = options;
  const schema = options.schema ?? DEFAULT_BLOCK_SCHEMA;
  const mappers = options.mappers ?? [];
  const run = blockCall(transport, schema, mappers);

  /** A call for the delivery loop, which handles a failure by throwing. */
  const call = async (
    fn: string,
    args: Readonly<Record<string, unknown>>,
  ): Promise<unknown> => run(fn, args, (value) => value).orThrow();

  const emitEvent = blockEmitter<NotificationsEvents>(options);

  function emit<
    T extends
      | "notification.created"
      | `notification.${DeliveryEventKind | "failed"}`,
  >(type: T, data: NotificationsEvents[T], tenant: string | null): void {
    emitEvent(type, data, `notifications/${data.notificationId}`, tenant);
  }

  const render = (
    item: NotificationItem,
    locale?: string,
    hydrated?: H,
  ): Rendered => {
    if (!options.render) {
      return item;
    }

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

    if (!avatars || typeof path !== "string" || path === "") {
      return actor;
    }

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

    if (ids.length === 0) {
      return new Map();
    }

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

  /**
   * Parses each item's data with its type's schema, before `hydrate` and
   * `render` see it.
   */
  const parsed = async (
    items: readonly NotificationItem[],
  ): Promise<Result<ParsedItem[]>> => {
    const out: ParsedItem[] = [];

    for (const item of items) {
      const schemaOf = Object.hasOwn(options.types, item.type)
        ? options.types[item.type]
        : undefined;

      if (schemaOf === undefined) {
        const extra = await fields.read(item.fields);

        if (!extra.ok) {
          return extra;
        }

        out.push({ ...item, fields: extra.data });
        continue;
      }

      const data = await validate(
        schemaOf,
        item.data,
        `${item.type} data of notification ${item.id}`,
      );

      if (!data.ok) {
        return err({ ...data.error, hint: "NOTIFICATION_DATA_INVALID" });
      }

      const extra = await fields.read(item.fields);

      if (!extra.ok) {
        return extra;
      }

      out.push({ ...item, data: data.data, fields: extra.data });
    }

    return ok(out);
  };

  const decorate = (
    items: readonly NotificationItem[],
    listOptions: Pick<ListOptions, "locale" | "include">,
  ): AsyncResult<readonly NotificationOf<K, F>[]> =>
    AsyncResult.from(async () => {
      const valid = await parsed(items);

      if (!valid.ok) {
        return valid;
      }

      return rendered(valid.data, listOptions);
    });

  const rendered = async (
    items: readonly ParsedItem[],
    listOptions: Pick<ListOptions, "locale" | "include">,
  ): Promise<Result<readonly NotificationOf<K, F>[]>> => {
    try {
      const locale = listOptions.locale;
      const context = locale === undefined ? {} : { locale };

      const [hydrated, actors] = await Promise.all([
        options.hydrate ? options.hydrate(items, context) : undefined,
        listOptions.include?.includes("actor") ? actorsOf(items) : undefined,
      ]);

      const out = items.map(
        (item): Rendered & { readonly fields: RowFields<F> } => {
          const text = {
            ...render(item, locale, hydrated),
            fields: item.fields,
          };

          return actors
            ? {
                ...text,
                actor: item.actorId ? (actors.get(item.actorId) ?? null) : null,
              }
            : text;
        },
      );

      // SAFETY: `parsed` gave each item of a listed type the output of its
      // type's schema and its fields the output of `options.fields`, which
      // is what NotificationOf<K, F> pairs with that type.
      return ok(out as readonly NotificationOf<K, F>[]);
    } catch (cause) {
      return err(toBlockError(cause, mappers));
    }
  };

  const channelList = deliveryChannels(options);

  const audience =
    options.audience ??
    options.server?.authorization?.delivery?.audience ??
    (options.server?.authorization === undefined
      ? undefined
      : subjectReaders(transport, { schema }));

  const claimedOf = (
    channel: NotificationChannel,
    row: Record<string, unknown>,
  ): Claimed => {
    const notification = isRecord(row["notification"])
      ? toItem(row["notification"])
      : undefined;

    if (!notification) {
      throw new TypeError("claim returned no notification");
    }

    return {
      message: {
        deliveryId: String(row["delivery_id"]),
        channel: channel.name,
        attempts: Number(row["attempts"] ?? 1),
        userId: String(row["user_id"]),
        email: nullableText(row["email"]),
        locale: nullableText(row["locale"]),
        notification,
      },
      suppressed: nullableText(row["suppressed"]),
    };
  };

  const fail = async (
    channel: NotificationChannel,
    message: NotificationMessage,
    error: string,
    maxAttempts: number,
  ): Promise<"failed"> => {
    await call("complete_notification_delivery", {
      delivery: message.deliveryId,
      status: "pending",
      error,
      max_attempts: maxAttempts,
    });
    emit(
      "notification.failed",
      { ...deliveryData(message, channel.name), error },
      message.notification.tenant,
    );

    return "failed";
  };

  const skip = async (
    message: NotificationMessage,
    error: string,
  ): Promise<"skipped"> => {
    await call("complete_notification_delivery", {
      delivery: message.deliveryId,
      status: "skipped",
      error,
    });

    return "skipped";
  };

  /**
   * Sends a claimed batch: suppressed addresses are skipped first, then each
   * notification's remaining recipients go through `audience` once.
   */
  async function deliverBatch(
    channel: NotificationChannel,
    rows: readonly Record<string, unknown>[],
    maxAttempts: number,
  ): Promise<("sent" | "skipped" | "failed")[]> {
    const claimed = rows.map((row) => claimedOf(channel, row));
    const outcomes: ("sent" | "skipped" | "failed")[] = [];
    const byEvent = new Map<string, NotificationMessage[]>();

    for (const { message, suppressed } of claimed) {
      if (suppressed !== null) {
        outcomes.push(await skip(message, `suppressed: ${suppressed}`));
        continue;
      }

      const group = byEvent.get(message.notification.eventId) ?? [];
      group.push(message);
      byEvent.set(message.notification.eventId, group);
    }

    for (const messages of byEvent.values()) {
      const notification = messages[0]!.notification;

      const subscribers = messages.map((message) => ({
        principal: message.userId,
        kind: "user" as const,
        message,
      }));

      const checked = await allowedSubscribers(
        audience,
        subscriberEventOf(notification),
        subscribers,
      );

      if (!checked.ok) {
        const error = `audience check failed: ${errorText(checked.cause)}`;

        for (const message of messages) {
          outcomes.push(await fail(channel, message, error, maxAttempts));
        }

        continue;
      }

      const allowed = new Set(
        checked.allowed.map((subscriber) => subscriber.message),
      );

      for (const message of messages) {
        if (!allowed.has(message)) {
          outcomes.push(await skip(message, "audience"));
        }
      }

      for (const [locale, group] of byLocale(
        messages.filter((message) => allowed.has(message)),
      )) {
        const hydrated = await hydrateFor(group, locale);

        for (const message of group) {
          outcomes.push(
            await deliverOne(channel, message, maxAttempts, hydrated),
          );
        }
      }
    }

    return outcomes;
  }

  /**
   * `hydrate` once for a locale's messages. A throwing hydrate fails only those
   * deliveries, inside `deliverOne`.
   */
  const hydrateFor = async (
    messages: readonly NotificationMessage[],
    locale: string | null,
  ): Promise<Hydration<H>> => {
    if (!options.hydrate) {
      return { ok: true, value: undefined };
    }

    try {
      return {
        ok: true,
        value: await options.hydrate(
          messages.map((message) => message.notification),
          locale === null ? {} : { locale },
        ),
      };
    } catch (cause) {
      return { ok: false, cause };
    }
  };

  async function deliverOne(
    channel: NotificationChannel,
    message: NotificationMessage,
    maxAttempts: number,
    hydration: Hydration<H>,
  ): Promise<"sent" | "skipped" | "failed"> {
    const notification = message.notification;

    try {
      if (!hydration.ok) {
        throw hydration.cause;
      }

      const text = options.render
        ? options.render(notification, {
            ...(message.locale === null ? {} : { locale: message.locale }),
            ...(hydration.value === undefined
              ? {}
              : { hydrated: hydration.value }),
          })
        : undefined;

      const result = await channel.send({
        ...message,
        ...(text === undefined ? {} : { text }),
        ...(hydration.value === undefined ? {} : { hydrated: hydration.value }),
      });

      const status = result?.status ?? "sent";
      await call("complete_notification_delivery", {
        delivery: message.deliveryId,
        status,
        provider: result?.provider ?? null,
        provider_message_id: result?.providerMessageId ?? null,
        ...(result?.templateKey === undefined
          ? {}
          : { template_key: result.templateKey }),
      });

      if (status === "sent") {
        emit(
          "notification.delivered",
          deliveryData(message, channel.name),
          notification.tenant,
        );
      }

      return status;
    } catch (cause) {
      return fail(channel, message, errorText(cause), maxAttempts);
    }
  }

  /**
   * `send_notification`'s argument for one send, after the type's schema and
   * the fields.
   */
  const prepare = async (
    type: string,
    input: SendInput<unknown, F>,
  ): Promise<Result<Record<string, unknown>>> => {
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

    if (!data.ok) {
      return err(data.error);
    }

    const extra =
      input.fields === undefined
        ? ok(undefined)
        : await fields.write({ ...input.fields });

    if (!extra.ok) {
      return extra;
    }

    if (
      input.permission !== undefined &&
      (input.tenant === undefined || input.tenant === "")
    ) {
      const message = "A permission audience needs a tenant";

      return err(
        dbError("validation", message, {
          issues: [{ path: ["tenant"], message }],
          hint: "NOTIFICATION_PERMISSION_NEEDS_TENANT",
        }),
      );
    }

    return ok({
      type,
      data: data.data,
      recipients: input.recipients ?? [],
      tenant: input.tenant,
      permission: input.permission,
      subject_type: input.subject?.type,
      subject_id: input.subject?.id,
      subject_label: input.subject?.label,
      summary: input.summary,
      action_path: input.actionPath,
      actions: input.actions,
      priority: input.priority,
      key: input.key,
      channels: input.channels,
      include_actor: input.includeActor,
      activity: input.activity,
      resolved: input.resolved,
      actor: input.actorId,
      watchers: input.watchers,
      exclude: input.exclude,
      fields: extra.data,
    });
  };

  const sentOf = (value: unknown): SentNotification | null =>
    isRecord(value) && value["id"] !== null && value["id"] !== undefined
      ? {
          id: String(value["id"]),
          recipients: (Array.isArray(value["recipients"])
            ? value["recipients"]
            : []
          ).map(String),
        }
      : null;

  /** Announces a sent notification and runs `onSent`. */
  const settle = async (
    sent: SentNotification | null,
    type: string,
    tenant: string | undefined,
  ): Promise<Result<SentNotification | null>> => {
    if (sent === null) {
      return ok(null);
    }

    const { id, recipients } = sent;
    emit(
      "notification.created",
      { notificationId: id, type, recipientIds: recipients },
      tenant ?? null,
    );

    if (options.onSent) {
      try {
        await options.onSent({ id, type, tenant: tenant ?? null, recipients });
      } catch (cause) {
        return err(toDbError(cause));
      }
    }

    return ok(sent);
  };

  const notifications: Notifications<K, F> = {
    send(type, input) {
      return AsyncResult.from(async () => {
        const notification = await prepare(type, input);

        if (!notification.ok) {
          return notification;
        }

        const sent = await run(
          "send_notification",
          { notification: notification.data },
          sentOf,
        );

        return sent.ok ? settle(sent.data, type, input.tenant) : sent;
      });
    },
    sendMany(items) {
      return AsyncResult.from(async () => {
        const prepared = await Promise.all(
          items.map((item) => prepare(item.type, item)),
        );

        const valid = prepared.flatMap((result, index) =>
          result.ok ? [{ index, notification: result.data }] : [],
        );

        const sent =
          valid.length === 0
            ? ok([])
            : await run(
                "send_notifications",
                { events: valid.map((entry) => entry.notification) },
                (value) =>
                  batchResultsOf(
                    value,
                    valid.length,
                    "notification",
                    sentOf,
                    mappers,
                  ),
              );

        if (!sent.ok) {
          return sent;
        }

        const results: Result<SentNotification | null>[] = prepared.map(
          (result) =>
            result.ok
              ? err(dbError("unexpected", "The notification was not sent"))
              : result,
        );

        for (const [position, { index }] of valid.entries()) {
          const result = sent.data[position];
          const item = items[index];

          if (result === undefined || item === undefined) {
            continue;
          }

          results[index] = result.ok
            ? await settle(result.data, item.type, item.tenant)
            : result;
        }

        return ok(results);
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
          ...cursorOf(pageOf(listOptions).cursor),
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
          ...(input.resolution === undefined
            ? {}
            : { resolution: input.resolution }),
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

      const channels = channelList.filter(
        (channel) => !wanted || wanted.includes(channel.name),
      );

      const spent = budget(deliverOptions.budgetMs);
      const batch = deliverOptions.batch ?? 50;
      const counts = { sent: 0, skipped: 0, failed: 0 };
      // Channels are independent, so a slow provider doesn't hold up the
      // others; each channel's deliveries go out in order.
      await Promise.all(
        channels.map(async (channel) => {
          while (!spent.expired()) {
            const claimed = await call("claim_notification_deliveries", {
              channel: channel.name,
              max_items: batch,
              lease: deliverOptions.lease ?? "5 minutes",
              max_attempts: deliverOptions.maxAttempts ?? 5,
            });

            const rows = (Array.isArray(claimed) ? claimed : []).filter(
              isRecord,
            );

            const outcomes = await deliverBatch(
              channel,
              rows,
              deliverOptions.maxAttempts ?? 5,
            );

            for (const outcome of outcomes) {
              counts[outcome] += 1;
            }

            if (rows.length < batch) {
              break;
            }
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
    suppress(input) {
      return run(
        "suppress_notification_address",
        {
          address: input.address,
          reason: input.reason,
          channel: input.channel ?? "email",
          provider: input.provider ?? null,
          provider_event_id: input.providerEventId ?? null,
          detail: input.detail ?? {},
        },
        (value) => value === true,
      );
    },
    unsuppress(address, channel = "email") {
      return run(
        "unsuppress_notification_address",
        { address, channel },
        (value) => value === true,
      );
    },
    suppressions(suppressionOptions = {}) {
      return run(
        "list_notification_suppressions",
        { max_items: suppressionOptions.limit ?? 50 },
        (value) =>
          (Array.isArray(value) ? value : [])
            .filter(isRecord)
            .flatMap((row): NotificationSuppression[] => {
              const reason = SUPPRESSION_REASONS.find(
                (entry) => entry === row["reason"],
              );

              return reason === undefined
                ? []
                : [
                    {
                      channel: String(row["channel"]),
                      address: String(row["address"]),
                      userId: nullableText(row["user_id"]),
                      reason,
                      provider: nullableText(row["provider"]),
                      createdAt: nullableInstant(row["created_at"]),
                    },
                  ];
            }),
      );
    },
    recordDeliveryEvent(input) {
      return run(
        "record_delivery_event",
        {
          provider: input.provider,
          provider_message_id: input.providerMessageId,
          kind: input.kind,
          provider_event_id: input.providerEventId ?? null,
          occurred_at: input.occurredAt?.toString() ?? null,
          detail: input.detail ?? {},
          suppress: input.suppress ?? null,
        },
        recordedDeliveryEventOf,
      ).map((recorded) => {
        if (recorded !== null) {
          emitDeliveryEvent(
            emitEvent,
            recorded,
            input.provider,
            input.providerEventId ?? null,
          );
        }

        return recorded;
      });
    },
    subjectDeliveries(deliveryOptions) {
      return run(
        "list_subject_deliveries",
        {
          subject_type: deliveryOptions.subject.type,
          subject_id: deliveryOptions.subject.id,
          tenant: deliveryOptions.tenant ?? null,
          max_items: deliveryOptions.limit ?? 50,
        },
        (value) =>
          (Array.isArray(value) ? value : [])
            .filter(isRecord)
            .map(subjectDeliveryOf),
      );
    },
    sink(sinkOptions) {
      const sendEach = async (
        chunk: readonly SinkNotification<K>[],
      ): Promise<readonly Result<SentNotification | null>[]> => {
        const results: Result<SentNotification | null>[] = [];

        for (const item of chunk) {
          results.push(await hooked.send(item.type, item));
        }

        return results;
      };

      return {
        async send(events) {
          const items: SinkNotification<K>[] = [];

          for (const event of events) {
            const type = stripTypePrefix(event.type, sinkOptions.typePrefix);
            const mapped = await sinkOptions.map({ ...event, type });

            if (mapped === null) {
              continue;
            }

            const tenant =
              typeof event["partitionkey"] === "string"
                ? event["partitionkey"]
                : undefined;

            items.push({
              ...mapped,
              key: mapped.key ?? event.id,
              ...(mapped.tenant === undefined && tenant !== undefined
                ? { tenant }
                : {}),
            });
          }

          let failure: DbException | undefined;

          // A rule on send must see every sink delivery, so it skips the batch.
          const perEvent = options.hooks?.send !== undefined;

          for (const chunk of chunksOf(items, MAX_BATCH)) {
            const results = perEvent
              ? ok(await sendEach(chunk))
              : await hooked.sendMany(chunk);

            if (!results.ok) {
              failure ??= new DbException(results.error);
              continue;
            }

            for (const result of results.data) {
              if (!result.ok) {
                failure ??= new DbException(result.error);
              }
            }
          }

          if (failure !== undefined) {
            throw failure;
          }
        },
      };
    },
  };

  const hooked = withBlockHooks(notifications, options.hooks, {
    block: "notifications",
    ...(options.events ? { logger: options.events.logger } : {}),
  });

  return hooked;
}
