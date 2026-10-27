import type {
  Adapter,
  AdapterPostableMessage,
  Attachment,
  ChatInstance,
  EmojiValue,
  FetchOptions,
  FetchResult,
  ListThreadsOptions,
  ListThreadsResult,
  RawMessage,
  Root,
  StreamChunk,
  ThreadInfo,
  ThreadSummary,
  WebhookOptions,
} from "chat";

import {
  BaseFormatConverter,
  ChatError,
  defaultEmojiResolver,
  Message,
  NotImplementedError,
  parseMarkdown,
  RateLimitError,
  stringifyMarkdown,
} from "chat";

import type { Inbox } from "../blocks/inbox/inbox.ts";
import type { Conversation, InboxMessage } from "../blocks/inbox/types.ts";
import type { MessageFile } from "../blocks/messaging/messaging.ts";
import type { IdentityRef } from "../core/contracts/authorization-hooks.ts";
import type { DbError, DbErrorKind } from "../core/errors.ts";
import type { AsyncResult } from "../core/result.ts";
import type { StreamStore } from "../streams/store.ts";
import type { BotJobsOptions } from "./identity.ts";

import {
  isRecord,
  optionalText,
  randomToken,
  toInstant,
} from "../core/block-helpers.ts";
import { writeToStore } from "../streams/tee.ts";
import { botJobs } from "./identity.ts";

const PREFIX = "inbox:";
const KNOWN_THREADS = 1000;

class MarkdownConverter extends BaseFormatConverter {
  fromAst(ast: Root): string {
    return stringifyMarkdown(ast).trimEnd();
  }
  toAst(text: string): Root {
    return parseMarkdown(text);
  }
}

const converter = new MarkdownConverter();

/**
 * The job the `inbox` module queues for a contact message while `bot_mode =
 * 'bot'`.
 */
export interface InboxBotJob {
  readonly conversation_id: string;
  readonly message_id: string;
  readonly thread_id?: string;
  readonly inbox_id?: string;
}

export interface InboxAdapterOptions {
  /** `createInbox` on a service transport: the bot writes as the service. */
  readonly inbox: Inbox;
  /** The bot's name on its messages and reactions. Defaults to `bot`. */
  readonly userName?: string;
  /**
   * Checks a request `handleWebhook` gets, such as a shared secret or a
   * signature. Without it `handleWebhook` answers 401; bot jobs go through
   * `dispatch` instead.
   */
  readonly verify?: (request: Request) => boolean | Promise<boolean>;
  /**
   * Stores streamed replies so a reader can resume them; the stream id lands in
   * the message's `metadata.stream_id`.
   */
  readonly streams?: StreamStore;
  /**
   * Issues a ticket for the contact's linked user before the bot's handlers
   * run, so they read and write as that user: `dispatch` resolves
   * `inboxIdentityOf(contactId)` through `principalByIdentity` (or the server's
   * `identities` hook) and calls `ticketFor` for a `kind: "user"` link, as
   * `botJobs` does. Read it with `ticketOf(message)`. A contact with no link
   * stays a visitor and gets no ticket.
   */
  readonly identities?: Omit<BotJobsOptions<unknown, unknown>, "enqueue">;
  /**
   * Reads a scanned attachment, such as from Storage with the service role. The
   * bot gets each clean file with its attachment id in `fetchMetadata`; with
   * `download` it can also read the bytes.
   */
  readonly download?: (file: MessageFile) => Promise<ArrayBuffer>;
  /**
   * The concurrency scope `getConcurrencyScope()` returns, such as the tenant
   * id when one `Chat` instance serves several tenants' inboxes.
   */
  readonly concurrencyScope?: string;
  /**
   * The inbox `openDM(contactId)` opens a bot conversation in. Without it the
   * adapter has no `openDM`, so `chat.openDM()` and the DM fallback of
   * `postEphemeral` are not available.
   */
  readonly dmInbox?: string;
}

/** The parts of an inbox thread id, `inbox:<inbox id>:<conversation id>`. */
export interface InboxThread {
  readonly inboxId: string;
  readonly conversationId: string;
}

export interface InboxAdapter extends Adapter<InboxThread, InboxMessage> {
  readonly name: "inbox";
  /**
   * Hands a queued bot job to Chat SDK: loads the contact's message and runs
   * the bot's handlers. Other authors are skipped. The options reach
   * `processMessage`; with `waitUntil` the whole job runs in the background and
   * the call returns at once.
   */
  dispatch(job: InboxBotJob, options?: WebhookOptions): Promise<void>;
  /**
   * The ticket `dispatch` issued for the message's linked user, for
   * `forContext({ ticket })`, while its handlers run; `undefined` for a
   * visitor, after `dispatch` returns, or without the `identities` option.
   */
  ticketOf(message: Message<InboxMessage>): string | undefined;
}

/**
 * The `IdentityRef` of an inbox contact: `kind: "chat"`, `provider: "inbox"`
 * and the contact id.
 */
export function inboxIdentityOf(contactId: string): IdentityRef {
  return { kind: "chat", provider: "inbox", value: contactId };
}

/** The thread id of an inbox conversation: `inbox:<inbox id>:<conversation id>`. */
export function inboxThreadId(thread: InboxThread): string {
  return `${PREFIX}${thread.inboxId}:${thread.conversationId}`;
}

/**
 * Splits an inbox thread id. Throws a `ChatError` with code `INVALID_THREAD_ID`
 * for any other shape, including the older `inbox:<conversation id>` form.
 */
export function decodeInboxThreadId(threadId: string): InboxThread {
  const rest = threadId.startsWith(PREFIX) ? threadId.slice(PREFIX.length) : "";
  const split = rest.lastIndexOf(":");

  if (split <= 0 || split === rest.length - 1) {
    throw new ChatError(
      `"${threadId}" is not an inbox thread id`,
      "INVALID_THREAD_ID",
    );
  }

  return {
    inboxId: rest.slice(0, split),
    conversationId: rest.slice(split + 1),
  };
}

/** The conversation id of an inbox thread id. */
export function conversationIdOf(threadId: string): string {
  return decodeInboxThreadId(threadId).conversationId;
}

const CHAT_ERROR_CODES: Readonly<Record<DbErrorKind, string>> = {
  not_found: "NOT_FOUND",
  unauthorized: "AUTH_FAILED",
  forbidden: "PERMISSION_DENIED",
  conflict: "CONFLICT",
  foreign_key: "VALIDATION_ERROR",
  check: "VALIDATION_ERROR",
  not_null: "VALIDATION_ERROR",
  exclusion: "CONFLICT",
  invalid_input: "VALIDATION_ERROR",
  invalid_value: "VALIDATION_ERROR",
  raised: "VALIDATION_ERROR",
  timeout: "NETWORK_ERROR",
  serialization: "CONFLICT",
  network: "NETWORK_ERROR",
  aborted: "ABORTED",
  invalid_request: "VALIDATION_ERROR",
  validation: "VALIDATION_ERROR",
  multiple_rows: "CONFLICT",
  stale: "CONFLICT",
  max_affected: "CONFLICT",
  rate_limited: "RATE_LIMITED",
  quota_exceeded: "RATE_LIMITED",
  unsupported: "NOT_IMPLEMENTED",
  unexpected: "UNEXPECTED",
};

/**
 * A `DbError` as the error Chat SDK adapters throw: `RateLimitError` with
 * `retryAfterMs` for `rate_limited` and `quota_exceeded`, `NotImplementedError`
 * for `unsupported`, and otherwise a `ChatError` whose code follows the adapter
 * codes (`NOT_FOUND`, `AUTH_FAILED`, `PERMISSION_DENIED`, `VALIDATION_ERROR`,
 * `NETWORK_ERROR`). The `DbError` is the `cause`.
 */
export function chatErrorOf(error: DbError): ChatError {
  if (error.kind === "rate_limited" || error.kind === "quota_exceeded") {
    return new RateLimitError(
      error.message,
      error.retryAfter === undefined ? undefined : error.retryAfter * 1000,
      error,
    );
  }

  if (error.kind === "unsupported") {
    return new NotImplementedError(error.message, error.table, error);
  }

  return new ChatError(error.message, CHAT_ERROR_CODES[error.kind], error);
}

async function must<T>(result: AsyncResult<T>): Promise<T> {
  const settled = await result;

  if (!settled.ok) {
    throw chatErrorOf(settled.error);
  }

  return settled.data;
}

/** The card in a message, kept in `metadata.card` for a client to render. */
function cardOf(message: AdapterPostableMessage): unknown {
  if (typeof message !== "object") {
    return undefined;
  }

  if ("card" in message) {
    return message.card;
  }

  return "type" in message ? message : undefined;
}

function bodyOf(message: AdapterPostableMessage): {
  readonly body: string;
  readonly format: "text" | "markdown";
} {
  if (typeof message === "string") {
    return { body: message, format: "text" };
  }

  if ("raw" in message) {
    return { body: message.raw, format: "text" };
  }

  if ("markdown" in message) {
    return { body: message.markdown, format: "markdown" };
  }

  return { body: converter.renderPostable(message), format: "markdown" };
}

function inboxIdOfChannel(channelId: string): string {
  const inboxId = channelId.startsWith(PREFIX)
    ? channelId.slice(PREFIX.length)
    : "";

  if (inboxId.length === 0 || inboxId.includes(":")) {
    throw new ChatError(
      `"${channelId}" is not an inbox channel id`,
      "INVALID_CHANNEL_ID",
    );
  }

  return inboxId;
}

type ConversationCursor = Pick<Conversation, "id" | "lastMessageAt">;

function encodeCursor(conversation: ConversationCursor): string {
  return JSON.stringify({
    id: conversation.id,
    lastMessageAt: conversation.lastMessageAt?.toString() ?? null,
  });
}

function decodeCursor(cursor: string): ConversationCursor {
  let value: unknown;

  try {
    value = JSON.parse(cursor);
  } catch {
    value = undefined;
  }

  if (
    !isRecord(value) ||
    typeof value["id"] !== "string" ||
    (value["lastMessageAt"] !== null &&
      typeof value["lastMessageAt"] !== "string")
  ) {
    throw new ChatError("invalid listThreads cursor", "VALIDATION_ERROR");
  }

  return {
    id: value["id"],
    lastMessageAt:
      value["lastMessageAt"] === null
        ? null
        : toInstant(value["lastMessageAt"]),
  };
}

const emojiOf = (value: EmojiValue | string): string =>
  defaultEmojiResolver.toDiscord(value);

function attachmentsOf(
  message: InboxMessage,
  download: InboxAdapterOptions["download"],
): Attachment[] {
  return message.attachments.flatMap((file) => {
    if (file.status !== "clean") {
      return [];
    }

    const type = file.mimeType?.startsWith("image/")
      ? "image"
      : file.mimeType?.startsWith("video/")
        ? "video"
        : file.mimeType?.startsWith("audio/")
          ? "audio"
          : "file";

    return [
      {
        type,
        name: file.name,
        fetchMetadata: { attachmentId: file.id },
        ...(file.mimeType === undefined ? {} : { mimeType: file.mimeType }),
        ...(file.size === undefined ? {} : { size: file.size }),
        ...(download === undefined ? {} : { fetchData: () => download(file) }),
      },
    ];
  });
}

async function* textOnly(
  source: AsyncIterable<string | StreamChunk>,
): AsyncIterable<string> {
  for await (const chunk of source) {
    if (typeof chunk === "string") {
      yield chunk;
    } else if (chunk.type === "markdown_text") {
      yield chunk.text;
    }
  }
}

/**
 * A Chat SDK adapter for the in-app inbox: the bot reads and writes the `inbox`
 * module's conversations, so one `Chat` instance answers the widget and the
 * other channels. Contact messages reach the bot as jobs on the module's bot
 * queue; pass them to `dispatch`.
 */
export function inboxAdapter(options: InboxAdapterOptions): InboxAdapter {
  const { inbox, dmInbox } = options;
  const userName = options.userName ?? "bot";
  let chat: ChatInstance | undefined;
  const tickets = new Map<string, string>();
  const threads = new Map<string, string>();

  const remember = (threadId: string): InboxThread => {
    const thread = decodeInboxThreadId(threadId);
    threads.delete(thread.conversationId);
    threads.set(thread.conversationId, threadId);

    if (threads.size > KNOWN_THREADS) {
      const [oldest] = threads.keys();

      if (oldest !== undefined) {
        threads.delete(oldest);
      }
    }

    return thread;
  };

  const threadOf = (message: InboxMessage): string => {
    const threadId = threads.get(message.conversationId);

    if (threadId === undefined) {
      throw new ChatError(
        `inboxAdapter: no thread seen for conversation ${message.conversationId}`,
        "INVALID_THREAD_ID",
      );
    }

    return threadId;
  };

  const ticketJobs =
    options.identities === undefined
      ? undefined
      : botJobs<Message<InboxMessage>, string | undefined>({
          ...options.identities,
          enqueue: (_message, { ticket }) => ticket,
        });

  const parse = (
    raw: InboxMessage,
    threadId: string,
  ): Message<InboxMessage> => {
    const isBot = raw.authorType === "bot" || raw.authorType === "system";

    const userId =
      raw.authorType === "bot" ? userName : (raw.authorId ?? raw.authorType);

    const name =
      optionalText(raw.metadata["author_name"]) ??
      (raw.authorType === "contact" ? "visitor" : userId);

    return new Message<InboxMessage>({
      id: raw.id,
      threadId,
      text: raw.body,
      formatted:
        raw.format === "markdown"
          ? parseMarkdown(raw.body)
          : {
              type: "root",
              children: [
                {
                  type: "paragraph",
                  children: [{ type: "text", value: raw.body }],
                },
              ],
            },
      raw,
      author: {
        userId,
        userName: name,
        fullName: name,
        isBot,
        isMe: raw.authorType === "bot",
        ...(raw.authorType === "system" ? { isSystem: true } : {}),
      },
      metadata: {
        dateSent: new Date((raw.sentAt ?? raw.createdAt).epochMilliseconds),
        edited: raw.editedAt !== undefined,
        ...(raw.editedAt === undefined
          ? {}
          : { editedAt: new Date(raw.editedAt.epochMilliseconds) }),
      },
      attachments: attachmentsOf(raw, options.download),
    });
  };

  const rawOf = (
    message: InboxMessage,
    threadId: string,
  ): RawMessage<InboxMessage> => ({ id: message.id, raw: message, threadId });

  const post = async (
    threadId: string,
    body: string,
    format: "text" | "markdown",
    metadata?: Readonly<Record<string, unknown>>,
    replyTo?: string,
  ): Promise<RawMessage<InboxMessage>> =>
    rawOf(
      await must(
        inbox.messages.send(remember(threadId).conversationId, {
          body,
          format,
          authorType: "bot",
          metadata: { author_name: userName, ...metadata },
          ...(replyTo === undefined ? {} : { replyTo }),
        }),
      ),
      threadId,
    );

  const postMessage = (
    threadId: string,
    message: AdapterPostableMessage,
    replyTo?: string,
  ): Promise<RawMessage<InboxMessage>> => {
    const { body, format } = bodyOf(message);
    const card = cardOf(message);

    return post(
      threadId,
      body,
      format,
      card === undefined ? undefined : { card },
      replyTo,
    );
  };

  const summaryOf = async (
    conversation: Conversation,
  ): Promise<ThreadSummary<InboxMessage>[]> => {
    const threadId = inboxThreadId({
      inboxId: conversation.inboxId,
      conversationId: conversation.id,
    });

    const [first] = await must(
      inbox.messages.list(conversation.id, { limit: 1, direction: "forward" }),
    );

    if (first === undefined) {
      return [];
    }

    return [
      {
        id: threadId,
        rootMessage: parse(first, threadId),
        ...(conversation.lastMessageAt === null
          ? {}
          : {
              lastReplyAt: new Date(
                conversation.lastMessageAt.epochMilliseconds,
              ),
            }),
      },
    ];
  };

  const run = async (
    instance: ChatInstance,
    job: InboxBotJob,
    webhook: WebhookOptions,
  ): Promise<void> => {
    const message = await must(inbox.messages.get(job.message_id));

    if (
      message?.conversationId !== job.conversation_id ||
      message.authorType !== "contact" ||
      message.kind !== "message"
    ) {
      return;
    }

    const conversation =
      job.inbox_id !== undefined && ticketJobs === undefined
        ? undefined
        : await must(inbox.conversations.get(message.conversationId));

    const inboxId = job.inbox_id ?? conversation?.inboxId;

    if (inboxId === undefined) {
      return;
    }

    const threadId = inboxThreadId({
      inboxId,
      conversationId: message.conversationId,
    });

    remember(threadId);
    const parsed = parse(message, threadId);
    const contactId = conversation?.contactId;

    if (ticketJobs !== undefined && contactId !== undefined) {
      const { result } = await ticketJobs.enqueue(
        inboxIdentityOf(contactId),
        parsed,
      );

      if (result !== undefined) {
        tickets.set(message.id, result);
      }
    }

    try {
      await instance.processMessage(adapter, threadId, parsed, webhook);
    } finally {
      tickets.delete(message.id);
    }
  };

  const dispatch = (
    job: InboxBotJob,
    webhook: WebhookOptions = {},
  ): Promise<void> => {
    if (!chat) {
      return Promise.reject(
        new ChatError("inboxAdapter: initialize() has not run", "NOT_READY"),
      );
    }

    const { waitUntil, ...rest } = webhook;

    if (waitUntil === undefined) {
      return run(chat, job, rest);
    }

    const logger = chat.getLogger("inbox");
    const task = run(chat, job, rest);

    waitUntil(
      rest.propagateHandlerErrors === true
        ? task
        : task.catch((error: unknown) => {
            logger.error("inbox bot job failed", {
              messageId: job.message_id,
              error,
            });
          }),
    );

    return Promise.resolve();
  };

  const adapter: InboxAdapter = {
    name: "inbox",
    userName,
    botUserId: userName,
    lockScope: "thread",
    initialize: (instance) => {
      chat = instance;

      return Promise.resolve();
    },
    ...(options.concurrencyScope === undefined
      ? {}
      : { getConcurrencyScope: () => options.concurrencyScope }),
    ...(dmInbox === undefined
      ? {}
      : {
          openDM: async (contactId: string): Promise<string> => {
            const conversation = await must(
              inbox.conversations.open(dmInbox, {
                contact: contactId,
                botMode: "bot",
              }),
            );

            return inboxThreadId({
              inboxId: conversation.inboxId,
              conversationId: conversation.id,
            });
          },
        }),
    encodeThreadId: inboxThreadId,
    decodeThreadId: decodeInboxThreadId,
    channelIdFromThreadId: (threadId) =>
      `${PREFIX}${decodeInboxThreadId(threadId).inboxId}`,
    isDM: () => true,
    parseMessage: (raw) => parse(raw, threadOf(raw)),
    renderFormatted: (content) => converter.fromAst(content),
    dispatch,
    ticketOf: (message) => tickets.get(message.id),
    handleWebhook: async (request, webhook) => {
      if (!options.verify || !(await options.verify(request))) {
        return new Response("unauthorized", { status: 401 });
      }

      let job: unknown;

      try {
        job = await request.json();
      } catch {
        return new Response("invalid JSON", { status: 400 });
      }

      if (
        !isRecord(job) ||
        typeof job["conversation_id"] !== "string" ||
        typeof job["message_id"] !== "string"
      ) {
        return new Response("expected conversation_id and message_id", {
          status: 400,
        });
      }

      await dispatch(
        {
          conversation_id: job["conversation_id"],
          message_id: job["message_id"],
          ...(typeof job["inbox_id"] === "string"
            ? { inbox_id: job["inbox_id"] }
            : {}),
        },
        webhook,
      );

      return new Response("ok", { status: 200 });
    },
    postMessage: (threadId, message) => postMessage(threadId, message),
    reply: (threadId, messageId, message) =>
      postMessage(threadId, message, messageId),
    editMessage: async (threadId, messageId, message) =>
      rawOf(
        await must(inbox.messages.edit(messageId, bodyOf(message).body)),
        threadId,
      ),
    deleteMessage: async (_threadId, messageId) => {
      await must(inbox.messages.remove(messageId));
    },
    addReaction: async (_threadId, messageId, value) => {
      await must(
        inbox.messages.react(messageId, emojiOf(value), {
          present: true,
          actor: userName,
        }),
      );
    },
    removeReaction: async (_threadId, messageId, value) => {
      await must(
        inbox.messages.react(messageId, emojiOf(value), {
          present: false,
          actor: userName,
        }),
      );
    },
    startTyping: async (threadId) => {
      await must(
        inbox.conversations.typing(conversationIdOf(threadId), true, userName),
      );
    },
    endTyping: async (threadId) => {
      await must(
        inbox.conversations.typing(conversationIdOf(threadId), false, userName),
      );
    },
    // The inbox keeps one read mark per conversation, so reading a message
    // marks the whole conversation read.
    markAsRead: async (threadId, _messageId) => {
      await must(inbox.conversations.markRead(conversationIdOf(threadId)));
    },
    fetchMessage: async (threadId, messageId) => {
      const { conversationId } = remember(threadId);
      const message = await must(inbox.messages.get(messageId));

      return message?.conversationId === conversationId
        ? parse(message, threadId)
        : null;
    },
    fetchMessages: async (
      threadId,
      fetchOptions: FetchOptions = {},
    ): Promise<FetchResult<InboxMessage>> => {
      const { conversationId } = remember(threadId);
      const limit = fetchOptions.limit ?? 50;
      const direction = fetchOptions.direction ?? "backward";

      const cursor =
        fetchOptions.cursor === undefined
          ? undefined
          : toInstant(fetchOptions.cursor);

      const page = await must(
        inbox.messages.list(conversationId, {
          limit,
          direction,
          ...(cursor === undefined ? {} : { cursor }),
        }),
      );

      const visible = page.filter((message) => message.kind === "message");
      const edge = direction === "forward" ? page.at(-1) : page[0];

      return {
        messages: visible.map((message) => parse(message, threadId)),
        ...(edge !== undefined && page.length >= limit
          ? { nextCursor: (edge.sentAt ?? edge.createdAt).toString() }
          : {}),
      };
    },
    fetchChannelInfo: (channelId) =>
      new Promise((resolve) => {
        resolve({
          id: channelId,
          isDM: true,
          metadata: { inboxId: inboxIdOfChannel(channelId) },
        });
      }),
    listThreads: async (
      channelId,
      listOptions: ListThreadsOptions = {},
    ): Promise<ListThreadsResult<InboxMessage>> => {
      const inboxId = inboxIdOfChannel(channelId);
      const limit = listOptions.limit ?? 50;

      const page = await must(
        inbox.conversations.list(null, {
          inboxId,
          status: "all",
          limit,
          ...(listOptions.cursor === undefined
            ? {}
            : { cursor: decodeCursor(listOptions.cursor) }),
        }),
      );

      const threads = await Promise.all(page.map(summaryOf));
      const last = page.at(-1);

      return {
        threads: threads.flat(),
        ...(last !== undefined && page.length >= limit
          ? { nextCursor: encodeCursor(last) }
          : {}),
      };
    },
    fetchThread: async (threadId): Promise<ThreadInfo> => {
      const { inboxId, conversationId } = remember(threadId);
      const conversation = await must(inbox.conversations.get(conversationId));

      return {
        id: threadId,
        channelId: `${PREFIX}${inboxId}`,
        isDM: true,
        metadata: conversation
          ? {
              inboxId: conversation.inboxId,
              contactId: conversation.contactId,
              status: conversation.status,
              botMode: conversation.botMode,
              subject: conversation.subject,
            }
          : {},
      };
    },
    stream: async (threadId, source, streamOptions) => {
      const { conversationId } = remember(threadId);
      await inbox.conversations.typing(conversationId, true, userName);
      let text = "";
      const chunks = textOnly(source);
      const store = options.streams;

      const streamId = store
        ? `${PREFIX}${conversationId}:${randomToken(9)}`
        : undefined;

      const readable = new ReadableStream<string>({
        async start(controller) {
          for await (const chunk of chunks) {
            if (streamOptions?.signal?.aborted) {
              break;
            }

            text += chunk;
            controller.enqueue(chunk);
          }

          controller.close();
        },
      });

      if (store && streamId) {
        await writeToStore(store, streamId, readable);
      } else {
        const reader = readable.getReader();

        while (!(await reader.read()).done) {
          // Every chunk is read so the producer can finish.
        }
      }

      await inbox.conversations.typing(conversationId, false, userName);

      if (text.trim().length === 0) {
        return null;
      }

      return post(
        threadId,
        text,
        "markdown",
        streamId === undefined ? undefined : { stream_id: streamId },
      );
    },
  };

  return adapter;
}
