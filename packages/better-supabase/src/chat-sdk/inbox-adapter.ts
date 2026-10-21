import type {
  Adapter,
  AdapterPostableMessage,
  Attachment,
  ChatInstance,
  EmojiValue,
  FetchOptions,
  FetchResult,
  RawMessage,
  Root,
  StreamChunk,
  ThreadInfo,
} from "chat";

import {
  BaseFormatConverter,
  defaultEmojiResolver,
  Message,
  parseMarkdown,
  stringifyMarkdown,
} from "chat";

import type { Inbox } from "../blocks/inbox/inbox.ts";
import type { InboxMessage } from "../blocks/inbox/types.ts";
import type { IdentityRef } from "../core/contracts/authorization-hooks.ts";
import type { StreamStore } from "../streams/store.ts";

import {
  isRecord,
  optionalText,
  randomToken,
  toInstant,
} from "../core/block-helpers.ts";
import { writeToStore } from "../streams/tee.ts";
import { type BotJobsOptions, botJobs } from "./identity.ts";

const PREFIX = "inbox:";

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
}

export interface InboxAdapter extends Adapter<string, InboxMessage> {
  readonly name: "inbox";
  /**
   * Hands a queued bot job to Chat SDK: loads the contact's message and runs
   * the bot's handlers. Other authors are skipped.
   */
  dispatch(job: InboxBotJob): Promise<void>;
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

/** `inbox:<conversation id>` to the conversation id. */
export function conversationIdOf(threadId: string): string {
  if (!threadId.startsWith(PREFIX) || threadId.length === PREFIX.length) {
    throw new Error(`"${threadId}" is not an inbox thread id`);
  }

  return threadId.slice(PREFIX.length);
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

const emojiOf = (value: EmojiValue | string): string =>
  typeof value === "string" ? value : defaultEmojiResolver.toGChat(value);

function attachmentsOf(message: InboxMessage): Attachment[] {
  return message.attachments.flatMap((file) => {
    const url = file.url;

    if (url === undefined) {
      return [];
    }

    const type = file.contentType?.startsWith("image/")
      ? "image"
      : file.contentType?.startsWith("video/")
        ? "video"
        : file.contentType?.startsWith("audio/")
          ? "audio"
          : "file";

    return [
      {
        type,
        url,
        ...(file.name === undefined ? {} : { name: file.name }),
        ...(file.contentType === undefined
          ? {}
          : { mimeType: file.contentType }),
        ...(file.size === undefined ? {} : { size: file.size }),
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
  const { inbox } = options;
  const userName = options.userName ?? "bot";
  let chat: ChatInstance | undefined;
  const tickets = new Map<string, string>();

  const ticketJobs =
    options.identities === undefined
      ? undefined
      : botJobs<Message<InboxMessage>, string | undefined>({
          ...options.identities,
          enqueue: (_message, { ticket }) => ticket,
        });

  const parseMessage = (raw: InboxMessage): Message<InboxMessage> => {
    const isBot = raw.authorType === "bot" || raw.authorType === "system";

    const userId =
      raw.authorType === "bot" ? userName : (raw.authorId ?? raw.authorType);

    const name =
      optionalText(raw.metadata["author_name"]) ??
      (raw.authorType === "contact" ? "visitor" : userId);

    return new Message<InboxMessage>({
      id: raw.id,
      threadId: `${PREFIX}${raw.conversationId}`,
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
        dateSent: new Date(raw.createdAt.epochMilliseconds),
        edited: raw.editedAt !== null,
        ...(raw.editedAt === null
          ? {}
          : { editedAt: new Date(raw.editedAt.epochMilliseconds) }),
      },
      attachments: attachmentsOf(raw),
    });
  };

  const rawOf = (message: InboxMessage): RawMessage<InboxMessage> => ({
    id: message.id,
    raw: message,
    threadId: `${PREFIX}${message.conversationId}`,
  });

  const post = async (
    threadId: string,
    body: string,
    format: "text" | "markdown",
    metadata?: Readonly<Record<string, unknown>>,
  ): Promise<RawMessage<InboxMessage>> =>
    rawOf(
      await inbox.messages
        .send(conversationIdOf(threadId), {
          body,
          format,
          authorType: "bot",
          metadata: { author_name: userName, ...metadata },
        })
        .orThrow(),
    );

  const dispatch = async (job: InboxBotJob): Promise<void> => {
    if (!chat) {
      throw new Error("inboxAdapter: initialize() has not run");
    }

    const message = await inbox.messages.get(job.message_id).orThrow();

    if (
      message?.conversationId !== job.conversation_id ||
      message.authorType !== "contact" ||
      message.kind !== "message"
    ) {
      return;
    }

    const parsed = parseMessage(message);

    if (ticketJobs !== undefined && message.authorId !== null) {
      const { result } = await ticketJobs.enqueue(
        inboxIdentityOf(message.authorId),
        parsed,
      );

      if (result !== undefined) {
        tickets.set(message.id, result);
      }
    }

    try {
      await chat.processMessage(
        adapter,
        `${PREFIX}${message.conversationId}`,
        parsed,
      );
    } finally {
      tickets.delete(message.id);
    }
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
    encodeThreadId: (conversationId) => `${PREFIX}${conversationId}`,
    decodeThreadId: conversationIdOf,
    channelIdFromThreadId: () => "inbox",
    isDM: () => true,
    parseMessage,
    renderFormatted: (content) => converter.fromAst(content),
    dispatch,
    ticketOf: (message) => tickets.get(message.id),
    handleWebhook: async (request) => {
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

      await dispatch({
        conversation_id: job["conversation_id"],
        message_id: job["message_id"],
      });

      return new Response("ok", { status: 200 });
    },
    postMessage: (threadId, message) => {
      const { body, format } = bodyOf(message);

      return post(threadId, body, format);
    },
    editMessage: async (_threadId, messageId, message) =>
      rawOf(
        await inbox.messages.edit(messageId, bodyOf(message).body).orThrow(),
      ),
    deleteMessage: async (_threadId, messageId) => {
      await inbox.messages.remove(messageId).orThrow();
    },
    addReaction: async (_threadId, messageId, value) => {
      await inbox.messages
        .react(messageId, emojiOf(value), { present: true, actor: userName })
        .orThrow();
    },
    removeReaction: async (_threadId, messageId, value) => {
      await inbox.messages
        .react(messageId, emojiOf(value), { present: false, actor: userName })
        .orThrow();
    },
    startTyping: async (threadId) => {
      await inbox.conversations
        .typing(conversationIdOf(threadId), true, userName)
        .orThrow();
    },
    endTyping: async (threadId) => {
      await inbox.conversations
        .typing(conversationIdOf(threadId), false, userName)
        .orThrow();
    },
    markAsRead: async (threadId) => {
      await inbox.conversations.markRead(conversationIdOf(threadId)).orThrow();
    },
    fetchMessage: async (threadId, messageId) => {
      const message = await inbox.messages.get(messageId).orThrow();

      return message && message.conversationId === conversationIdOf(threadId)
        ? parseMessage(message)
        : null;
    },
    fetchMessages: async (
      threadId,
      fetchOptions: FetchOptions = {},
    ): Promise<FetchResult<InboxMessage>> => {
      const limit = fetchOptions.limit ?? 50;

      const before =
        fetchOptions.cursor === undefined
          ? undefined
          : toInstant(fetchOptions.cursor);

      const page = await inbox.messages
        .list(conversationIdOf(threadId), {
          limit,
          ...(before === undefined ? {} : { cursor: before }),
        })
        .orThrow();

      const visible = page.filter((message) => message.kind === "message");
      const oldest = page[0];

      return {
        messages: visible.map(parseMessage),
        ...(oldest !== undefined && page.length >= limit
          ? { nextCursor: oldest.createdAt.toString() }
          : {}),
      };
    },
    fetchThread: async (threadId): Promise<ThreadInfo> => {
      const conversation = await inbox.conversations
        .get(conversationIdOf(threadId))
        .orThrow();

      return {
        id: threadId,
        channelId: "inbox",
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
      const conversationId = conversationIdOf(threadId);
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
