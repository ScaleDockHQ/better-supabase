import type { BlockOptions } from "../core/block-helpers.ts";
import type { EventHub } from "../core/events.ts";
import type { CredentialProvider } from "../credentials/provider.ts";
import type { EventSink } from "../events/cloud-event.ts";
import type { AiFiles } from "./ai-files/ai-files.ts";
import type { AiTaskOutcome } from "./ai-tasks/ai-tasks.ts";

import { isRecord } from "../core/block-helpers.ts";
import { forwardBlockEvents } from "../events/cloud-event.ts";

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
}

/** What each block factory receives: the shared options and its siblings. */
export interface BlockContext extends BlockOptions {
  readonly credentials?: CredentialProvider;
  readonly events?: EventHub;
  /** The `aiFiles` block, for knowledge. */
  readonly files?: AiFiles;
  /** Sends `aiTaskNotification` through the `notifications` block, for ai-tasks. */
  readonly notify?: (outcome: AiTaskOutcome) => unknown;
}

/** Builds one block, usually a block creator such as `createOrganizations`. */
export type BlockFactory<T = unknown> = (context: BlockContext) => T;

export type BlockFactories = Readonly<Record<string, BlockFactory>> & {
  readonly aiFiles?: BlockFactory<AiFiles>;
};

export type Blocks<F extends BlockFactories> = {
  readonly [K in keyof F]: F[K] extends BlockFactory<infer T> ? T : never;
} & {
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
      readonly data: Readonly<Record<string, unknown>>;
    },
  ): unknown;
}

const isNotificationSender = (value: unknown): value is NotificationSender =>
  isRecord(value) && typeof value["send"] === "function";

/**
 * Builds the blocks in `factories` with one set of options, and wires the
 * siblings they share: the `aiFiles` block into knowledge, `credentials`
 * into connectors, ai-providers and the builder, the `notifications` block
 * into ai-tasks (with `aiTaskNotification`), and block events into `audit`.
 * Only the blocks you pass are imported, so the rest stay out of the bundle.
 */
export function createBlocks<const F extends BlockFactories>(
  options: CreateBlocksOptions,
  factories: F,
): Blocks<F> {
  const { credentials, events, audit, aiTaskNotification, ...shared } = options;
  if (audit !== undefined && events === undefined)
    throw new TypeError("createBlocks: `audit` needs `events` to forward");
  const built = new Map<string, unknown>();
  const building = new Set<string>();

  const notify =
    aiTaskNotification === undefined || factories["notifications"] === undefined
      ? undefined
      : (outcome: AiTaskOutcome): unknown => {
          const notifications = build("notifications");
          if (!isNotificationSender(notifications))
            throw new TypeError("The notifications block has no send method");
          return notifications.send(aiTaskNotification, {
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
        };

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
      const block = factory(contextFor(name));
      built.set(name, block);
      return block;
    } finally {
      building.delete(name);
    }
  }

  const blocks: Record<string, unknown> = {};
  for (const name of Object.keys(factories)) blocks[name] = build(name);
  const stop =
    audit === undefined || events === undefined
      ? undefined
      : forwardBlockEvents({ events }, audit, { source: BLOCK_EVENT_SOURCE });
  blocks["close"] = () => stop?.();
  // SAFETY: `blocks` holds the result of every factory under its own key,
  // plus `close`, which is what `Blocks<F>` describes.
  return blocks as Blocks<F>;
}
