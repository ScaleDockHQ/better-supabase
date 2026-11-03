import type {
  ChatLike,
  InboundHandler,
  InboundHandlerOptions,
  InboxWebhookOptions,
} from "./channels.ts";
import type { ChatInboundEvent, ChatWebhookResult } from "./store.ts";

import { inboundHandler, webhook } from "./channels.ts";
import { isInboundStore } from "./store.ts";

export interface ChatWebhookPipelineOptions
  extends
    Omit<
      InboundHandlerOptions,
      "chat" | "propagateHandlerErrors" | "deduplicate"
    >,
    Omit<InboxWebhookOptions, "adapter" | "inbox" | "passthroughHandler"> {
  /**
   * The Chat instance with your handlers. `process` replays stored events into
   * it, so the handlers run in the worker.
   */
  readonly chat: ChatLike;
  /**
   * A second Chat instance with the same adapter and no handlers, on its own
   * state. `receive` runs each request through it, so the adapter checks the
   * signature, answers the platform's challenges and parses the event without
   * running a handler. Give its state a prefix other than `chat`'s (for
   * `createSupabaseState`, a different `keyPrefix`, such as
   * `chat-sdk:receive`): both runs would otherwise share one duplicate list,
   * and the replay would drop every event as already seen.
   */
  readonly receiveChat: ChatLike;
  /** The adapter's name in both Chat instances. */
  readonly adapter: string;
  /**
   * Decides what a failed replay does: return `{ retryIn }` to hand the delay
   * to a queue handler (`{ retryIn, permanent }`) instead of throwing. Without
   * it, or when it returns nothing, the error is rethrown.
   */
  readonly retry?: (
    error: unknown,
    event: ChatInboundEvent,
  ) => ChatWebhookResult | undefined;
}

export interface ChatWebhookPipeline {
  /** The route handler: checks the request through the adapter, then stores it. */
  readonly receive: (request: Request) => Promise<Response>;
  /**
   * Replays one stored event into `chat` with Chat SDK's duplicate check off
   * and handler errors propagated. It resolves when every handler task ended
   * and throws when one failed, so the job retries; with `retry` it may return
   * a delay instead.
   */
  readonly process: (
    event: ChatInboundEvent,
  ) => Promise<ChatWebhookResult | undefined>;
  /** The handler `process` runs on: `drain`, `mirror` and `importFiles`. */
  readonly handler: InboundHandler;
}

function prefixOf(chat: ChatLike): string | undefined {
  const state: unknown = chat.getState();

  return typeof state === "object" &&
    state !== null &&
    "keyPrefix" in state &&
    typeof state.keyPrefix === "string"
    ? state.keyPrefix
    : undefined;
}

/**
 * Splits a channel webhook into a receiving half and a processing half.
 * `receive` answers the platform from a handler-less Chat instance and stores
 * the raw event in the sink (or the inbox). `process` replays it later into the
 * Chat instance that has your handlers, once per queue attempt. Both instances
 * need their own state prefix: a shared one makes the replay look like a
 * duplicate. That throws a `TypeError` here, when the prefixes match.
 */
export function chatWebhookPipeline(
  options: ChatWebhookPipelineOptions,
): ChatWebhookPipeline {
  const { chat, receiveChat, adapter, retry, inbox, ...rest } = options;

  if (
    chat === receiveChat ||
    chat.getState() === receiveChat.getState() ||
    (prefixOf(chat) !== undefined && prefixOf(chat) === prefixOf(receiveChat))
  ) {
    throw new TypeError(
      'chatWebhookPipeline: `chat` and `receiveChat` share one state prefix, so the replay would be dropped as a duplicate; give the receiving state its own `keyPrefix` (for example "chat-sdk:receive")',
    );
  }

  const receiver = receiveChat.webhooks[adapter];

  if (receiver === undefined) {
    throw new TypeError(
      `chatWebhookPipeline: \`receiveChat\` has no adapter named "${adapter}"`,
    );
  }

  const handler = inboundHandler({
    ...rest,
    inbox,
    chat,
    propagateHandlerErrors: true,
    deduplicate: "never",
  });

  const receive = webhook({
    ...rest,
    // A `ChatInboundStore` has no webhook store; events go to `sink`.
    ...(isInboundStore(inbox) ? {} : { inbox }),
    adapter,
    passthroughHandler: receiver,
    verify: async (request, body) => {
      if (
        options.verify !== undefined &&
        !(await options.verify(request, body))
      ) {
        return false;
      }

      const tasks: Promise<unknown>[] = [];

      const response = await receiver(
        new Request(request.url, {
          method: request.method,
          headers: request.headers,
          body,
        }),
        { waitUntil: (task) => void tasks.push(task) },
      );

      await Promise.all(tasks);

      return response.status < 400;
    },
  });

  return {
    receive,
    handler,
    process: async (event) => {
      try {
        await handler.process(event);

        return;
      } catch (error) {
        const decision = retry?.(error, event);

        if (decision === undefined) {
          throw error;
        }

        return decision;
      }
    },
  };
}
