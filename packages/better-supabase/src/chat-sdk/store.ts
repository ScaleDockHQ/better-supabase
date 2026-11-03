import type { Inbox } from "../blocks/inbox/inbox.ts";
import type {
  Conversation,
  DeliveryStatus,
  InboundResult,
  InboxMessage,
  StoredInboundEvent,
} from "../blocks/inbox/types.ts";

import { isRecord } from "../core/block-helpers.ts";

type InboundInput = Parameters<Inbox["inbound"]["record"]>[0];

/** The staff reply an outbound job names, with its conversation. */
export interface ChatOutboundMessage {
  readonly message: InboxMessage;
  readonly conversation: Conversation;
}

/**
 * Where the Chat SDK helpers keep conversations and deliveries:
 * `inboundHandler`, `deliver`, `whatsappWindowOpen` and `maintain` take one
 * instead of an `Inbox`. Implement it to keep channel messages in your own
 * tables. Methods reject with the error that stopped them. `apiVersion` is the
 * contract's version; a breaking change gets a new one.
 */
export interface ChatInboundStore {
  readonly apiVersion: 1;
  /**
   * Records a message that arrived on a channel, opening the thread's
   * conversation when it has none. `duplicate` is true when the message's
   * `externalId` was already stored.
   */
  recordInbound(input: InboundInput): Promise<InboundResult>;
  /** Records a reply the platform accepted, with the platform's message id. */
  recordOutbound(input: {
    readonly messageId: string;
    readonly channel: string;
    readonly externalId: string;
  }): Promise<void>;
  /** Records a post that failed, so the job's retry is visible. */
  recordDeliveryAttempt(input: {
    readonly messageId: string;
    readonly channel: string;
    readonly status: DeliveryStatus;
    readonly externalId?: string;
    readonly error?: string;
  }): Promise<void>;
  /** A platform status callback; returns how many deliveries moved. */
  updateDeliveryStatus(input: {
    readonly channel: string;
    readonly externalId: string;
    readonly status: DeliveryStatus;
    readonly error?: string;
  }): Promise<number>;
  /** When the contact last wrote in the conversation, or `null`. */
  lastInboundAt(conversationId: string): Promise<Temporal.Instant | null>;
  /** The staff reply `deliver` posts and its conversation, or `null`. */
  outbound(messageId: string): Promise<ChatOutboundMessage | null>;
  /**
   * The store's own periodic work for `maintain`, such as waking snoozed
   * conversations. Leave it out when there is none.
   */
  maintain?(options: {
    readonly keepEvents?: number | string;
  }): Promise<{
    readonly woken: number;
    readonly published: number;
    readonly purgedEvents: number;
  }>;
}

/** The part of a stored webhook event `process` replays. */
export type ChatInboundEvent = Pick<
  StoredInboundEvent,
  "id" | "adapter" | "headers" | "body"
> & {
  /**
   * The number of this attempt, counting from 1. `inboundHandler`'s
   * `deduplicate: "first-attempt"` skips Chat SDK's duplicate check from the
   * second attempt on, so a retry reaches the handlers. Left out, the event
   * counts as a first attempt.
   */
  readonly attempt?: number;
};

/** What `webhook` hands a durable sink: the raw request, ready to replay. */
export interface ChatWebhookPayload {
  readonly adapter: string;
  readonly body: string;
  readonly headers: Readonly<Record<string, string>>;
  readonly inboxId?: string;
}

/** The event `webhook` stores in a sink. */
export interface ChatWebhookEvent {
  /** The platform's event id, or a random one. */
  readonly id: string;
  readonly payload: ChatWebhookPayload;
  readonly headers?: Readonly<Record<string, string>>;
  readonly tenant?: string | null;
}

/**
 * What `process` may return instead of throwing, for a worker that schedules
 * the retry itself. A webhook inbox handler can return it as is: `retryIn`
 * delays the next attempt.
 */
export interface ChatWebhookResult {
  /** Seconds, or an interval string such as `"2 minutes"`. */
  readonly retryIn?: number | string;
}

/**
 * A durable place for verified webhook requests. The queue block's
 * `createWebhookInbox` fits it: pass the inbox itself, and replay each message
 * with `inboundHandler(...).process(chatEventOf(message))`.
 */
export interface ChatWebhookSink {
  /**
   * Stores the event. A rejection or a failed `Result` (an `AsyncResult` from a
   * block) answers the platform 503 so it retries.
   */
  store(event: ChatWebhookEvent): PromiseLike<unknown>;
}

/**
 * The replayable event in a webhook inbox message's `payload`, or `null`. The
 * message's `attempts` becomes the event's `attempt`.
 */
export function chatEventOf(message: {
  readonly id: string | number;
  readonly payload: unknown;
  /** The webhook inbox's count of claims, this one included. */
  readonly attempts?: number;
}): ChatInboundEvent | null {
  const { payload } = message;

  if (
    !isRecord(payload) ||
    typeof payload["adapter"] !== "string" ||
    typeof payload["body"] !== "string"
  ) {
    return null;
  }

  const headers: Record<string, string> = {};

  if (isRecord(payload["headers"])) {
    for (const [key, value] of Object.entries(payload["headers"])) {
      if (typeof value === "string") {
        headers[key] = value;
      }
    }
  }

  return {
    id: String(message.id),
    adapter: payload["adapter"],
    body: payload["body"],
    headers,
    ...(message.attempts === undefined ? {} : { attempt: message.attempts }),
  };
}

/** The store an `Inbox` or a store argument stands for. */
export function isInboundStore(
  value: Inbox | ChatInboundStore,
): value is ChatInboundStore {
  return "apiVersion" in value;
}

/** Adapts an `Inbox` on a service transport to `ChatInboundStore`. */
export function inboxStore(inbox: Inbox): ChatInboundStore {
  return {
    apiVersion: 1,
    recordInbound: (input) => inbox.inbound.record(input).orThrow(),
    recordOutbound: (input) =>
      inbox.deliveries
        .record({
          messageId: input.messageId,
          channel: input.channel,
          externalId: input.externalId,
          status: "sent",
        })
        .orThrow(),
    recordDeliveryAttempt: (input) =>
      inbox.deliveries
        .record({
          messageId: input.messageId,
          channel: input.channel,
          status: input.status,
          ...(input.externalId === undefined
            ? {}
            : { externalId: input.externalId }),
          ...(input.error === undefined ? {} : { error: input.error }),
        })
        .orThrow(),
    updateDeliveryStatus: (input) =>
      inbox.deliveries.setStatus(input).orThrow(),
    lastInboundAt: async (conversationId) => {
      const conversation = await inbox.conversations
        .get(conversationId)
        .orThrow();

      return conversation?.lastInboundAt ?? null;
    },
    outbound: async (messageId) => {
      const message = await inbox.messages.get(messageId).orThrow();

      if (message?.kind !== "message" || message.deletedAt !== undefined) {
        return null;
      }

      const conversation = await inbox.conversations
        .get(message.conversationId)
        .orThrow();

      return conversation ? { message, conversation } : null;
    },
    maintain: async (options) => ({
      woken: await inbox.wakeSnoozed().orThrow(),
      published: await inbox.publishDue().orThrow(),
      purgedEvents: await inbox.inbound
        .purge({ olderThan: options.keepEvents ?? "7 days" })
        .orThrow(),
    }),
  };
}

/** The store for an `Inbox` or a store. */
export function storeOf(value: Inbox | ChatInboundStore): ChatInboundStore {
  return isInboundStore(value) ? value : inboxStore(value);
}
