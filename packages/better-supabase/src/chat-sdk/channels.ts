import type {
  Adapter,
  AdapterPostableMessage,
  Attachment,
  Message,
  RawMessage,
  StateAdapter,
  WebhookOptions,
} from "chat";

import type { Inbox } from "../blocks/inbox/inbox.ts";
import type {
  Conversation,
  InboundResult,
  InboxMessage,
  MessageAttachment,
  StoredInboundEvent,
} from "../blocks/inbox/types.ts";
import type {
  CredentialProvider,
  CredentialRef,
  CredentialSubject,
  CredentialToken,
} from "../credentials/provider.ts";

import { errorText } from "../blocks/shared.ts";
import {
  DELIVERY_PARSERS,
  type DeliveryParser,
  type ParsedDeliveries,
} from "./delivery.ts";

/** The parts of a Chat SDK `Chat` the inbox helpers use. */
export interface ChatLike {
  readonly webhooks: Readonly<
    Record<
      string,
      (request: Request, options?: WebhookOptions) => Promise<Response>
    >
  >;
  getAdapter(name: string): Adapter | undefined;
  getState(): StateAdapter;
}

const APP: CredentialSubject = { type: "app" };
const ECHO_TTL_MS = 24 * 60 * 60 * 1000;
const echoKey = (adapter: string, id: string): string =>
  `better-supabase:inbox:echo:${adapter}:${id}`;

export interface ChannelAdapterOptions<A> {
  readonly credentials: CredentialProvider;
  /** The install's `credential_ref`, from `installations.get`. */
  readonly ref: CredentialRef;
  readonly subject?: CredentialSubject;
  /** Builds the platform adapter with the token, e.g. `(t) => createSlackAdapter({ botToken: t.token })`. */
  readonly create: (token: CredentialToken) => A | Promise<A>;
}

/** A platform adapter built from the token the credential provider holds, so no secret sits in env. */
export async function channelAdapter<A>(
  options: ChannelAdapterOptions<A>,
): Promise<A> {
  const token = await options.credentials
    .getToken(options.ref, { subject: options.subject ?? APP })
    .orThrow();
  return options.create(token);
}

export interface InboxWebhookOptions {
  /** `createInbox` on a service transport. */
  readonly inbox: Inbox;
  /** The adapter name the event is replayed into later. */
  readonly adapter: string;
  readonly inboxId?: string;
  readonly tenant?: string;
  /** With `ref`, checks the request with `credentials.verifyInbound` before storing it. */
  readonly credentials?: CredentialProvider;
  readonly ref?: CredentialRef;
  /** Checks the request when no credential ref does. Without either, every request is stored. */
  readonly verify?: (
    request: Request,
    body: string,
  ) => boolean | Promise<boolean>;
  /** The platform's event id, so a retried delivery is stored once. */
  readonly externalId?: (body: string, request: Request) => string | undefined;
  /**
   * Requests the platform answers synchronously, such as Meta's `GET`
   * verification or Slack's `url_verification`. They go straight to this
   * handler instead of the store. Defaults to `GET` requests and Slack
   * challenges, handed to `passthroughHandler`.
   */
  readonly passthrough?: (request: Request, body: string) => boolean;
  readonly passthroughHandler?: (request: Request) => Promise<Response>;
  /** Runs after the event is stored, e.g. `after(() => handler.drain())`. */
  readonly after?: (stored: {
    readonly id: string;
    readonly duplicate: boolean;
  }) => void;
}

const DROPPED_HEADERS = new Set(["cookie", "authorization", "x-forwarded-for"]);

const defaultPassthrough = (request: Request, body: string): boolean =>
  request.method === "GET" || body.includes('"type":"url_verification"');

/**
 * A route handler that verifies a channel webhook, stores the raw event in
 * the inbox's `inbound_events` and answers 200 at once. `inboundHandler`
 * replays it into Chat SDK later, so a slow bot never makes the platform
 * retry.
 */
export function webhook(
  options: InboxWebhookOptions,
): (request: Request) => Promise<Response> {
  const passthrough = options.passthrough ?? defaultPassthrough;
  return async (request) => {
    const body = await request.clone().text();
    if (passthrough(request, body)) {
      return options.passthroughHandler
        ? options.passthroughHandler(request)
        : new Response("not found", { status: 404 });
    }
    if (options.ref) {
      const provider = options.credentials;
      if (!provider?.verifyInbound)
        return new Response(
          "the credential provider cannot verify inbound requests",
          {
            status: 500,
          },
        );
      const verified = await provider.verifyInbound(request, options.ref);
      if (!verified.ok || !verified.data)
        return new Response("unauthorized", { status: 401 });
    } else if (options.verify && !(await options.verify(request, body))) {
      return new Response("unauthorized", { status: 401 });
    }
    const headers: Record<string, string> = {};
    request.headers.forEach((value, key) => {
      if (!DROPPED_HEADERS.has(key)) headers[key] = value;
    });
    const externalId = options.externalId?.(body, request);
    const stored = await options.inbox.inbound.store({
      adapter: options.adapter,
      body,
      headers,
      ...(externalId === undefined ? {} : { externalId }),
      ...(options.inboxId === undefined ? {} : { inboxId: options.inboxId }),
      ...(options.tenant === undefined ? {} : { tenant: options.tenant }),
    });
    if (!stored.ok)
      return new Response("could not store the event", { status: 503 });
    options.after?.(stored.data);
    return new Response("ok", { status: 200 });
  };
}

/** The thread a Chat SDK handler gets, as much as `mirror` needs. */
export interface MirrorThread {
  readonly id: string;
  readonly adapter: { readonly name: string };
}

export interface InboundHandlerOptions {
  readonly chat: ChatLike;
  /** `createInbox` on a service transport. */
  readonly inbox: Inbox;
  /** The inbox each adapter's threads land in, by adapter name. */
  readonly inboxes: Readonly<Record<string, string>>;
  /** Delivery status parsers by adapter name. Defaults to WhatsApp, Messenger, Instagram and Twilio. */
  readonly parsers?: Readonly<Record<string, DeliveryParser>>;
  /**
   * Copies a platform file into storage for the inbox. Without it a file
   * is kept only when it has a public URL; platform URLs often need the
   * bot's token, so copy them.
   */
  readonly copyFile?: (
    file: Attachment,
    context: { readonly adapter: string; readonly threadId: string },
  ) => Promise<MessageAttachment | null>;
  /** The URL replayed requests carry. Defaults to `https://inbox.local/<adapter>`. */
  readonly baseUrl?: string;
}

export interface DrainResult {
  readonly processed: number;
  readonly failed: number;
}

export interface InboundHandler {
  /** Replays one stored event: delivery statuses go to the inbox, the rest into Chat SDK. */
  process(event: StoredInboundEvent): Promise<void>;
  /** Processes pending events, oldest first. */
  drain(options?: {
    readonly limit?: number;
    readonly maxAttempts?: number;
  }): Promise<DrainResult>;
  /**
   * Records a channel message in the inbox, from a Chat SDK handler. Skips
   * bot messages, its own and the ones `deliver` posted (their echo);
   * returns `null` for those.
   */
  mirror(thread: MirrorThread, message: Message): Promise<InboundResult | null>;
}

/** Replays stored webhook events and mirrors channel messages into the inbox. */
export function inboundHandler(options: InboundHandlerOptions): InboundHandler {
  const { chat, inbox } = options;
  const parsers = options.parsers ?? DELIVERY_PARSERS;
  const baseUrl = options.baseUrl ?? "https://inbox.local";

  const applyDeliveries = async (
    adapter: string,
    parsed: ParsedDeliveries,
  ): Promise<void> => {
    for (const update of parsed.updates)
      await inbox.deliveries
        .setStatus({
          channel: channelFor(adapter),
          externalId: update.externalId,
          status: update.status,
          ...(update.error === undefined ? {} : { error: update.error }),
        })
        .orThrow();
  };

  const process = async (event: StoredInboundEvent): Promise<void> => {
    await inbox.inbound.setStatus(event.id, "processing").orThrow();
    try {
      const parsed = parsers[event.adapter]?.(event) ?? null;
      if (parsed) await applyDeliveries(event.adapter, parsed);
      if (parsed?.only) {
        await inbox.inbound.setStatus(event.id, "processed").orThrow();
        return;
      }
      const handle = chat.webhooks[event.adapter];
      if (!handle) {
        await inbox.inbound
          .setStatus(event.id, "ignored", `no adapter named ${event.adapter}`)
          .orThrow();
        return;
      }
      const tasks: Promise<unknown>[] = [];
      const response = await handle(
        new Request(`${baseUrl}/${encodeURIComponent(event.adapter)}`, {
          method: "POST",
          headers: event.headers,
          body: event.body,
        }),
        { waitUntil: (task) => void tasks.push(task) },
      );
      await Promise.all(tasks);
      if (response.status >= 400)
        throw new Error(`${event.adapter} answered ${String(response.status)}`);
      await inbox.inbound.setStatus(event.id, "processed").orThrow();
    } catch (error) {
      await inbox.inbound.setStatus(event.id, "failed", errorText(error));
      throw error;
    }
  };

  const files = async (
    message: Message,
    adapter: string,
    threadId: string,
  ): Promise<MessageAttachment[]> => {
    const out: MessageAttachment[] = [];
    for (const file of message.attachments) {
      if (options.copyFile) {
        const copied = await options.copyFile(file, { adapter, threadId });
        if (copied) out.push(copied);
      } else if (file.url !== undefined) {
        out.push({
          url: file.url,
          ...(file.name === undefined ? {} : { name: file.name }),
          ...(file.mimeType === undefined
            ? {}
            : { contentType: file.mimeType }),
          ...(file.size === undefined ? {} : { size: file.size }),
        });
      }
    }
    return out;
  };

  return {
    process,
    drain: async (drainOptions = {}) => {
      const events = await inbox.inbound
        .pending({
          limit: drainOptions.limit ?? 50,
          ...(drainOptions.maxAttempts === undefined
            ? {}
            : { maxAttempts: drainOptions.maxAttempts }),
        })
        .orThrow();
      let processed = 0;
      let failed = 0;
      for (const event of events) {
        try {
          await process(event);
          processed += 1;
        } catch {
          failed += 1;
        }
      }
      return { processed, failed };
    },
    mirror: async (thread, message) => {
      const adapter = thread.adapter.name;
      if (message.author.isMe || message.author.isBot === true) return null;
      const state = chat.getState();
      if ((await state.get(echoKey(adapter, message.id))) !== null) return null;
      const inboxId = options.inboxes[adapter];
      if (inboxId === undefined)
        throw new Error(`inboundHandler: no inbox for adapter "${adapter}"`);
      const attachments = await files(message, adapter, thread.id);
      return inbox.inbound
        .record({
          inboxId,
          threadId: thread.id,
          contact: {
            externalId: message.author.userId,
            name: message.author.fullName || message.author.userName,
            ...(message.author.email === undefined
              ? {}
              : { email: message.author.email }),
          },
          message: {
            body: message.text,
            externalId: message.id,
            ...(attachments.length > 0 ? { attachments } : {}),
          },
        })
        .orThrow();
    },
  };
}

const CHANNELS: Readonly<Record<string, string>> = { twilio: "sms" };
const channelFor = (adapter: string): string => CHANNELS[adapter] ?? adapter;

/** The job the `inbox` module queues for a staff reply on a channel inbox. */
export interface InboxOutboundJob {
  readonly message_id: string;
  readonly conversation_id: string;
  readonly inbox_id?: string;
}

export interface DeliverOptions {
  readonly chat: ChatLike;
  /** `createInbox` on a service transport. */
  readonly inbox: Inbox;
  /** The adapter that posts a conversation's replies. Defaults to the inbox's channel (`sms` posts with `twilio`). */
  readonly adapterFor?: (conversation: Conversation) => string;
  /**
   * The approved template to send when the channel's reply window is
   * closed, such as WhatsApp's 24 hours after the contact's last message.
   * Return `null` to post the message as is.
   */
  readonly template?: (context: {
    readonly conversation: Conversation;
    readonly message: InboxMessage;
    readonly adapter: Adapter;
  }) => Promise<AdapterPostableMessage | null> | AdapterPostableMessage | null;
}

/** True while WhatsApp's customer service window is open: within 24 hours of the contact's last message. */
export async function whatsappWindowOpen(
  inbox: Inbox,
  conversationId: string,
  now: Temporal.Instant = Temporal.Now.instant(),
): Promise<boolean> {
  const page = await inbox.messages
    .list(conversationId, { limit: 200 })
    .orThrow();
  const last = page.findLast(
    (message) => message.direction === "inbound" && message.kind === "message",
  );
  return (
    last !== undefined &&
    Temporal.Instant.compare(last.createdAt.add({ hours: 24 }), now) > 0
  );
}

/**
 * Posts a staff reply the `inbox` module queued on its channel, records
 * the delivery with the platform's message id, and remembers the id so
 * `mirror` skips the platform's echo. A failed post is recorded and thrown,
 * so the job retries.
 */
export function deliver(
  options: DeliverOptions,
): (job: InboxOutboundJob) => Promise<RawMessage | null> {
  const { chat, inbox } = options;
  return async (job) => {
    const message = await inbox.messages.get(job.message_id).orThrow();
    if (message?.kind !== "message" || message.deletedAt !== null) return null;
    const conversation = await inbox.conversations
      .get(message.conversationId)
      .orThrow();
    if (!conversation) return null;
    const name =
      options.adapterFor?.(conversation) ??
      (conversation.inbox?.channel === "sms"
        ? "twilio"
        : conversation.inbox?.channel);
    const adapter = name === undefined ? undefined : chat.getAdapter(name);
    if (!adapter || name === undefined)
      throw new Error(
        `deliver: no adapter for conversation ${conversation.id}`,
      );
    const channel = conversation.inbox?.channel ?? name;
    try {
      const template = await options.template?.({
        conversation,
        message,
        adapter,
      });
      const raw = await adapter.postMessage(
        conversation.threadId,
        template ??
          (message.format === "markdown"
            ? { markdown: message.body }
            : message.body),
      );
      await chat.getState().set(echoKey(name, raw.id), true, ECHO_TTL_MS);
      await inbox.deliveries
        .record({
          messageId: message.id,
          channel,
          externalId: raw.id,
          status: "sent",
        })
        .orThrow();
      return raw;
    } catch (error) {
      await inbox.deliveries.record({
        messageId: message.id,
        channel,
        status: "failed",
        error: errorText(error),
      });
      throw error;
    }
  };
}

export interface MaintainOptions {
  /** `createInbox` on a service transport. */
  readonly inbox: Inbox;
  /** Replays events a crashed request left pending. */
  readonly handler?: InboundHandler;
  /** `createSupabaseState(...)`: deletes expired locks, cache rows, lists and queues. */
  readonly state?: {
    purge(options?: { readonly batch?: number }): Promise<number>;
  };
  /** How long processed webhook events stay. Defaults to 7 days. */
  readonly keepEvents?: number | string;
}

export interface MaintainResult {
  readonly woken: number;
  readonly purgedEvents: number;
  readonly replayed: DrainResult;
  readonly purgedState: number;
}

/** The inbox's periodic work: wake snoozed conversations, replay and purge webhook events, sweep state. Run it from a cron job. */
export async function maintain(
  options: MaintainOptions,
): Promise<MaintainResult> {
  const woken = await options.inbox.wakeSnoozed().orThrow();
  const replayed = options.handler
    ? await options.handler.drain()
    : { processed: 0, failed: 0 };
  const purgedEvents = await options.inbox.inbound
    .purge({ olderThan: options.keepEvents ?? "7 days" })
    .orThrow();
  const purgedState = options.state ? await options.state.purge() : 0;
  return { woken, purgedEvents, replayed, purgedState };
}
