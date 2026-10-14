import type { BlockOptions } from "../core/block-helpers.ts";
import type { BlockHooks } from "../core/block-hooks.ts";
import type { EventHub } from "../core/events.ts";
import type { CredentialProvider } from "../credentials/provider.ts";
import type { EventSink } from "../events/cloud-event.ts";
import type { AiFiles } from "./ai-files/ai-files.ts";
import type { AiTaskOutcome } from "./ai-tasks/ai-tasks.ts";
import type { Metrics } from "./metrics/metrics.ts";
import type { DeliveryPayload } from "./reminders/schedule.ts";
import type { Search } from "./search/search.ts";

import { isRecord } from "../core/block-helpers.ts";
import { withBlockHooks } from "../core/block-hooks.ts";
import { forwardBlockEvents } from "../events/cloud-event.ts";
import { metricsSink, type MetricsSinkOptions } from "./metrics/sink.ts";
import { searchSink } from "./search/sink.ts";

/** The CloudEvents `source` of block events that `createBlocks` forwards. */
export const BLOCK_EVENT_SOURCE = "/better-supabase/blocks";

export interface CreateBlocksOptions extends BlockOptions {
  /** Connectors, ai-providers and the builder store their secrets here. */
  readonly credentials?: CredentialProvider;
  /** `betterSupabase.events`, for the block events of the blocks that emit them. */
  readonly events?: EventHub;
  /**
   * Where block events go, such as `auditLog.sink()`. Needs `events`; the
   * forwarding lasts until `close()`, so build these blocks once rather than
   * per request.
   */
  readonly audit?: EventSink;
  /**
   * The notification type ai-tasks sends for each finished run, through the
   * `notifications` block. Its data is `{ taskId, runId, ok, error?, chatId? }`.
   */
  readonly aiTaskNotification?: string;
  /**
   * The notification type a delivered reminder sends through the
   * `notifications` block, to the user who set it and the reminded
   * subject's watchers. Its data is `{ reminderId, occurrenceAt }`.
   */
  readonly reminderNotification?: string;
  /**
   * Event type to the metrics whose rows it adds, such as
   * `{ "order.placed": ["orders", "revenue"] }`, for `sinks.metrics`.
   */
  readonly metricEvents?: MetricsSinkOptions["on"];
  /** When an event's rows sit in time, for `sinks.metrics`. Default: the event's `time`. */
  readonly metricTime?: MetricsSinkOptions["time"];
}

/**
 * Outbox sinks over the blocks that consume events, for
 * `outbox.relayRoute({ consumers: { ...app.sinks } })`.
 */
export interface BlockSinks {
  /** `searchSink` over the `search` block: trash events drop and restore rows. */
  readonly search?: EventSink;
  /** `metricsSink` over the `metrics` block, with `metricEvents`. */
  readonly metrics?: EventSink;
}

/** What each block factory receives: the shared options and its siblings. */
export interface BlockContext extends BlockOptions {
  readonly credentials?: CredentialProvider;
  readonly events?: EventHub;
  /** The `aiFiles` block, for knowledge. */
  readonly files?: AiFiles;
  /** Sends `aiTaskNotification` through the `notifications` block, for ai-tasks. */
  readonly notify?: (outcome: AiTaskOutcome) => unknown;
  /** Sends `reminderNotification` through the `notifications` block, for reminders. */
  readonly notifyDelivery?: (delivery: DeliveryPayload) => unknown;
}

/** Builds one block, usually a block creator such as `createOrganizations`. */
export type BlockFactory<T = unknown> = (context: BlockContext) => T;

export type BlockFactories = Readonly<Record<string, BlockFactory>> & {
  readonly aiFiles?: BlockFactory<AiFiles>;
};

type BuiltBlocks<F extends BlockFactories> = {
  readonly [K in keyof F]: F[K] extends BlockFactory<infer T> ? T : never;
};

/** `withBlockHooks` hooks for each block, keyed by the names in `factories`. */
export type BlocksHooks<F extends BlockFactories> = {
  readonly [K in keyof F]?: BlockHooks<BuiltBlocks<F>[K]>;
};

export type Blocks<F extends BlockFactories> = BuiltBlocks<F> & {
  /** The outbox sinks of the `search` and `metrics` blocks, when built. */
  readonly sinks: BlockSinks;
  /** Stops forwarding block events to `audit`. */
  close(): void;
};

interface NotificationSender {
  send(
    type: string,
    input: {
      readonly recipients: readonly string[];
      readonly tenant: string;
      readonly key: string;
      readonly subject?: { readonly type: string; readonly id: string };
      readonly data: Readonly<Record<string, unknown>>;
    },
  ): unknown;
}

const isNotificationSender = (value: unknown): value is NotificationSender =>
  isRecord(value) && typeof value["send"] === "function";

const isSearch = (
  value: unknown,
): value is Pick<Search, "remove" | "refresh"> =>
  isRecord(value) &&
  typeof value["remove"] === "function" &&
  typeof value["refresh"] === "function";

const isMetrics = (value: unknown): value is Pick<Metrics, "rollup"> =>
  isRecord(value) && typeof value["rollup"] === "function";

function sinksOf(
  search: unknown,
  metrics: unknown,
  sink: {
    readonly on: MetricsSinkOptions["on"] | undefined;
    readonly time: MetricsSinkOptions["time"] | undefined;
  },
): BlockSinks {
  if (search !== undefined && !isSearch(search))
    throw new TypeError("The search block has no remove and refresh methods");
  if (metrics !== undefined && !isMetrics(metrics))
    throw new TypeError("The metrics block has no rollup method");
  return {
    ...(search === undefined ? {} : { search: searchSink(search) }),
    ...(metrics === undefined || sink.on === undefined
      ? {}
      : {
          metrics: metricsSink(metrics, {
            on: sink.on,
            ...(sink.time === undefined ? {} : { time: sink.time }),
          }),
        }),
  };
}

/**
 * Builds the blocks in `factories` with one set of options, and wires the
 * siblings they share: the `aiFiles` block into knowledge, `credentials`
 * into connectors, ai-providers and the builder, the `notifications` block
 * into ai-tasks (with `aiTaskNotification`) and reminders (with
 * `reminderNotification`), and block events into `audit`. `sinks` holds
 * outbox sinks over the `search` block (trash events) and the `metrics`
 * block (`metricEvents`), for the app's relay route.
 * Only the blocks you pass are imported, so the rest stay out of the bundle.
 * `hooks` wraps each block's methods with `withBlockHooks`, so siblings that
 * call a block (ai-tasks sending notifications) go through its hooks too.
 */
export function createBlocks<const F extends BlockFactories>(
  options: CreateBlocksOptions & {
    readonly hooks?: NoInfer<BlocksHooks<F>>;
  },
  factories: F,
): Blocks<F> {
  const {
    credentials,
    events,
    audit,
    aiTaskNotification,
    reminderNotification,
    metricEvents,
    metricTime,
    hooks,
    ...shared
  } = options;
  if (audit !== undefined && events === undefined)
    throw new TypeError("createBlocks: `audit` needs `events` to forward");
  if (metricEvents !== undefined && factories["metrics"] === undefined)
    throw new TypeError("createBlocks: `metricEvents` needs a `metrics` block");
  const built = new Map<string, unknown>();
  const building = new Set<string>();

  const sender = (): NotificationSender => {
    const notifications = build("notifications");
    if (!isNotificationSender(notifications))
      throw new TypeError("The notifications block has no send method");
    return notifications;
  };
  const hasNotifications = factories["notifications"] !== undefined;

  const notify =
    aiTaskNotification === undefined || !hasNotifications
      ? undefined
      : (outcome: AiTaskOutcome): unknown =>
          sender().send(aiTaskNotification, {
            recipients: [outcome.task.userId],
            tenant: outcome.task.organizationId,
            key: `ai-task-run:${outcome.run.id}`,
            data: {
              taskId: outcome.task.id,
              runId: outcome.run.id,
              ok: outcome.ok,
              ...(outcome.error === undefined ? {} : { error: outcome.error }),
              ...(outcome.chatId === undefined
                ? {}
                : { chatId: outcome.chatId }),
            },
          });

  const notifyDelivery =
    reminderNotification === undefined || !hasNotifications
      ? undefined
      : (delivery: DeliveryPayload): unknown =>
          sender().send(reminderNotification, {
            recipients: delivery.userId === undefined ? [] : [delivery.userId],
            tenant: delivery.organizationId,
            key: `reminder:${delivery.reminderId}:${delivery.occurrenceAt}`,
            ...(delivery.subjectType === undefined ||
            delivery.subjectId === undefined
              ? {}
              : {
                  subject: {
                    type: delivery.subjectType,
                    id: delivery.subjectId,
                  },
                }),
            data: {
              reminderId: delivery.reminderId,
              occurrenceAt: delivery.occurrenceAt,
            },
          });

  function contextFor(name: string): BlockContext {
    const files =
      name === "aiFiles" || factories.aiFiles === undefined
        ? undefined
        : build("aiFiles");
    return {
      ...shared,
      ...(credentials === undefined ? {} : { credentials }),
      ...(events === undefined ? {} : { events }),
      ...(files === undefined ? {} : { files }),
      ...(notify === undefined ? {} : { notify }),
      ...(notifyDelivery === undefined ? {} : { notifyDelivery }),
    };
  }

  function build(name: "aiFiles"): AiFiles;
  function build(name: string): unknown;
  function build(name: string): unknown {
    if (built.has(name)) return built.get(name);
    const factory = factories[name];
    if (factory === undefined) throw new TypeError(`No block named "${name}"`);
    if (building.has(name))
      throw new TypeError(`The "${name}" block depends on itself`);
    building.add(name);
    try {
      const created = factory(contextFor(name));
      const blockHooks: BlockHooks<object> | undefined = hooks?.[name];
      const block =
        blockHooks !== undefined && isRecord(created)
          ? withBlockHooks(created, blockHooks, {
              block: name,
              ...(events === undefined ? {} : { logger: events.logger }),
            })
          : created;
      built.set(name, block);
      return block;
    } finally {
      building.delete(name);
    }
  }

  const blocks: Record<string, unknown> = {};
  for (const name of Object.keys(factories)) blocks[name] = build(name);
  blocks["sinks"] = sinksOf(built.get("search"), built.get("metrics"), {
    on: metricEvents,
    time: metricTime,
  });
  const stop =
    audit === undefined || events === undefined
      ? undefined
      : forwardBlockEvents({ events }, audit, { source: BLOCK_EVENT_SOURCE });
  blocks["close"] = () => stop?.();
  // SAFETY: `blocks` holds the result of every factory under its own key,
  // plus `sinks` and `close`, which is what `Blocks<F>` describes.
  return blocks as Blocks<F>;
}
