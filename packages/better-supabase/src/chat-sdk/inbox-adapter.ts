import type {
  Adapter,
  AdapterPostableMessage,
  ChatInstance,
  FetchOptions,
  FetchResult,
  ListThreadsOptions,
  ListThreadsResult,
  RawMessage,
  ThreadInfo,
  ThreadSummary,
  WebhookOptions,
} from "chat";

import { ChatError, Message, NotImplementedError, parseMarkdown } from "chat";

import type { Inbox } from "../blocks/inbox/inbox.ts";
import type {
  Conversation,
  InboxMessage,
  InboxUpload,
} from "../blocks/inbox/types.ts";
import type { MessageFile } from "../blocks/messaging/messaging.ts";
import type { IdentityRef } from "../core/contracts/authorization-hooks.ts";
import type { StreamStore } from "../streams/store.ts";
import type { BotJobsOptions } from "./identity.ts";
import type {
  InboxActionEvent,
  InboxOutgoingFile,
  InboxReactionEvent,
} from "./inbox-adapter-parts.ts";

import {
  isRecord,
  optionalText,
  randomToken,
  toInstant,
} from "../core/block-helpers.ts";
import { writeToStore } from "../streams/tee.ts";
import { botJobs } from "./identity.ts";
import { eventDispatchers } from "./inbox-adapter-events.ts";
import {
  attachmentsOf,
  bodyOf,
  cardOf,
  converter,
  decodeCursor,
  emojiOf,
  encodeCursor,
  inboxIdOfChannel,
  must,
  PREFIX,
  textOnly,
} from "./inbox-adapter-helpers.ts";
import {
  aiGeneratedOf,
  byteLength,
  emptyMessage,
  outgoingFilesOf,
} from "./inbox-adapter-parts.ts";

export { chatErrorOf } from "./inbox-adapter-helpers.ts";

export type {
  InboxActionEvent,
  InboxActor,
  InboxOutgoingFile,
  InboxReactionEvent,
} from "./inbox-adapter-parts.ts";

const KNOWN_THREADS = 1000;

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
  /**
   * Writes the bytes of a file the bot posts, to the `bucket` and `path` of
   * `target` (for example `supabase.storage.from(bucket).upload(path, data)`
   * with the service role). The adapter creates the attachment before and
   * confirms it after. Without it, posting a message with files throws.
   */
  readonly upload?: (
    target: InboxUpload,
    file: InboxOutgoingFile,
  ) => Promise<void>;
  /**
   * Marks a streamed reply as AI generated (`metadata.ai_generated`), so a
   * client can label it. Defaults to true; a streamed reply is the model's.
   */
  readonly aiGeneratedStreams?: boolean;
  /**
   * The action id that stops the bot's turn: `dispatchAction` calls `abortTurn`
   * for the thread instead of the bot's handlers. Defaults to `chat:stop`.
   */
  readonly stopActionId?: string;
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
  /**
   * Hands a card button press to Chat SDK's `onAction` handlers. The stop
   * action (`stopActionId`) aborts the thread's running turn instead.
   */
  dispatchAction(
    event: InboxActionEvent,
    options?: WebhookOptions,
  ): Promise<void>;
  /** Hands a reaction to Chat SDK's `onReaction` handlers. */
  dispatchReaction(
    event: InboxReactionEvent,
    options?: WebhookOptions,
  ): Promise<void>;
}

/** The action id `inboxAdapter` treats as "stop the bot" by default. */
export const INBOX_STOP_ACTION = "chat:stop";

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
    attachments?: readonly string[],
  ): Promise<RawMessage<InboxMessage>> =>
    rawOf(
      await must(
        inbox.messages.send({
          conversationId: remember(threadId).conversationId,
          input: {
            body,
            format,
            authorType: "bot",
            metadata: { author_name: userName, ...metadata },
            ...(replyTo === undefined ? {} : { replyTo }),
            ...(attachments === undefined || attachments.length === 0
              ? {}
              : { attachments }),
          },
        }),
      ),
      threadId,
    );

  const uploadAll = async (
    conversationId: string,
    files: readonly InboxOutgoingFile[],
  ): Promise<string[]> => {
    if (files.length === 0) {
      return [];
    }

    if (options.upload === undefined) {
      throw new NotImplementedError(
        "inboxAdapter: posting files needs the `upload` option",
        "upload",
      );
    }

    const ids: string[] = [];

    for (const file of files) {
      const target = await must(
        inbox.messages.createUpload({
          conversationId,
          file: {
            name: file.name,
            size: byteLength(file.data),
            ...(file.mimeType === undefined ? {} : { mimeType: file.mimeType }),
          },
        }),
      );

      await options.upload(target, file);
      await must(inbox.messages.confirmUpload(target.id));
      ids.push(target.id);
    }

    return ids;
  };

  const postMessage = async (
    threadId: string,
    message: AdapterPostableMessage,
    replyTo?: string,
  ): Promise<RawMessage<InboxMessage>> => {
    const { body, format } = bodyOf(message);
    const card = cardOf(message);
    const { conversationId } = remember(threadId);

    const attachments = await uploadAll(
      conversationId,
      await outgoingFilesOf(message),
    );

    const metadata = {
      ...(card === undefined ? {} : { card }),
      ...(aiGeneratedOf(message) ? { ai_generated: true } : {}),
    };

    return post(
      threadId,
      body,
      format,
      Object.keys(metadata).length === 0 ? undefined : metadata,
      replyTo,
      attachments,
    );
  };

  /** The thread id of a conversation: the cache, the event's inbox or a read. */
  const threadIdFor = async (
    conversationId: string,
    inboxId: string | undefined,
  ): Promise<string | undefined> => {
    const known = threads.get(conversationId);

    if (known !== undefined) {
      return known;
    }

    const owner =
      inboxId ?? (await must(inbox.conversations.get(conversationId)))?.inboxId;

    return owner === undefined
      ? undefined
      : inboxThreadId({ inboxId: owner, conversationId });
  };

  const { dispatchAction, dispatchReaction } = eventDispatchers({
    chat: () => chat,
    adapter: () => adapter,
    threadFor: threadIdFor,
    remember,
    stopActionId: options.stopActionId ?? INBOX_STOP_ACTION,
  });

  const summaryOf = async (
    conversation: Conversation,
  ): Promise<ThreadSummary<InboxMessage>[]> => {
    const threadId = inboxThreadId({
      inboxId: conversation.inboxId,
      conversationId: conversation.id,
    });

    const [first] = await must(
      inbox.messages.list({
        conversationId: conversation.id,
        limit: 1,
        direction: "forward",
      }),
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
              inbox.conversations.open({
                inboxId: dmInbox,
                input: { contact: contactId, botMode: "bot" },
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
    dispatchAction,
    dispatchReaction,
    supportsTurnCancellation: true,
    rehydrateAttachment: (attachment) => {
      const attachmentId = attachment.fetchMetadata?.["attachmentId"];
      const { download } = options;

      if (download === undefined || typeof attachmentId !== "string") {
        return attachment;
      }

      const file: MessageFile = {
        id: attachmentId,
        name: attachment.name ?? "file",
        mimeType: attachment.mimeType,
        size: attachment.size,
        status: "clean",
      };

      return { ...attachment, fetchData: () => download(file) };
    },
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

      const inboxId =
        typeof job["inbox_id"] === "string"
          ? { inbox_id: job["inbox_id"] }
          : {};

      const user =
        isRecord(job["user"]) && typeof job["user"]["id"] === "string"
          ? {
              user: {
                id: job["user"]["id"],
                ...(typeof job["user"]["name"] === "string"
                  ? { name: job["user"]["name"] }
                  : {}),
              },
            }
          : {};

      if (job["type"] === "action" && typeof job["action_id"] === "string") {
        await dispatchAction(
          {
            conversation_id: job["conversation_id"],
            message_id: job["message_id"],
            action_id: job["action_id"],
            ...(typeof job["value"] === "string"
              ? { value: job["value"] }
              : {}),
            ...inboxId,
            ...user,
          },
          webhook,
        );

        return new Response("ok", { status: 200 });
      }

      if (
        job["type"] === "reaction" &&
        typeof job["emoji"] === "string" &&
        typeof job["added"] === "boolean"
      ) {
        await dispatchReaction(
          {
            conversation_id: job["conversation_id"],
            message_id: job["message_id"],
            emoji: job["emoji"],
            added: job["added"],
            ...inboxId,
            ...user,
          },
          webhook,
        );

        return new Response("ok", { status: 200 });
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
        await must(
          inbox.messages.edit({ messageId, body: bodyOf(message).body }),
        ),
        threadId,
      ),
    deleteMessage: async (_threadId, messageId) => {
      await must(inbox.messages.remove(messageId));
    },
    addReaction: async (_threadId, messageId, value) => {
      await must(
        inbox.messages.react({
          messageId,
          emoji: emojiOf(value),
          present: true,
          actor: userName,
        }),
      );
    },
    removeReaction: async (_threadId, messageId, value) => {
      await must(
        inbox.messages.react({
          messageId,
          emoji: emojiOf(value),
          present: false,
          actor: userName,
        }),
      );
    },
    startTyping: async (threadId) => {
      await must(
        inbox.conversations.typing({
          conversationId: conversationIdOf(threadId),
          typing: true,
          actor: userName,
        }),
      );
    },
    endTyping: async (threadId) => {
      await must(
        inbox.conversations.typing({
          conversationId: conversationIdOf(threadId),
          typing: false,
          actor: userName,
        }),
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
        inbox.messages.list({
          conversationId,
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
        inbox.conversations.list({
          tenant: null,
          filter: {
            inboxId,
            status: "all",
            limit,
            ...(listOptions.cursor === undefined
              ? {}
              : { cursor: decodeCursor(listOptions.cursor) }),
          },
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
      const { conversationId, inboxId } = remember(threadId);
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

      await inbox.conversations.typing({
        conversationId,
        typing: true,
        actor: userName,
      });

      try {
        if (store && streamId) {
          await writeToStore(store, streamId, readable);
        } else {
          const reader = readable.getReader();

          while (!(await reader.read()).done) {
            // Every chunk is read so the producer can finish.
          }
        }
      } finally {
        await inbox.conversations.typing({
          conversationId,
          typing: false,
          actor: userName,
        });
      }

      // Nothing to post: answer with a message that was never stored, so the
      // Chat SDK does not fall back to posting the stream again.
      if (text.trim().length === 0) {
        return rawOf(emptyMessage(conversationId, inboxId), threadId);
      }

      return post(threadId, text, "markdown", {
        ...(streamId === undefined ? {} : { stream_id: streamId }),
        ...(options.aiGeneratedStreams === false ? {} : { ai_generated: true }),
      });
    },
  };

  return adapter;
}
