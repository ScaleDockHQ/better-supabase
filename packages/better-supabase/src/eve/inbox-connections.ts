import type { Inbox, InboundInput } from "../blocks/inbox/inbox.ts";
import type {
  Conversation,
  StoredInboundEvent,
} from "../blocks/inbox/types.ts";
import type {
  CredentialProvider,
  CredentialRef,
} from "../credentials/provider.ts";
import type { EveDispatchOptions } from "./schedules.ts";
import type { EveSessionReply } from "./sync.ts";
import type { EveSessionAuth } from "./types.ts";

import { webhook } from "../chat-sdk/channels.ts";
import { DbException } from "../core/errors.ts";
import { errorText } from "../core/guards.ts";

/** One inbox channel connection, as its webhook route resolves it. */
export interface EveInboxConnection {
  /** The adapter name the stored event is replayed under. */
  readonly adapter: string;
  /** The organization that owns the connection. */
  readonly tenant: string;
  /** The inbox the connection's threads land in. */
  readonly inboxId?: string;
  /**
   * The connection's sealed credential. With `ref`, the request is checked with
   * `credentials.verifyInbound` before it is stored.
   */
  readonly credentials?: CredentialProvider;
  readonly ref?: CredentialRef;
  /** Checks the request when no credential ref does. */
  readonly verify?: (
    request: Request,
    body: string,
  ) => boolean | Promise<boolean>;
  /** The platform's event id, so a retried delivery is stored once. */
  readonly externalId?: (body: string, request: Request) => string | undefined;
  /** Answers the requests a platform checks synchronously, such as `GET`. */
  readonly passthroughHandler?: (request: Request) => Promise<Response>;
}

/** Options for `inboxConnectionWebhook`. */
export interface InboxConnectionWebhookOptions {
  /** `createInbox` on a service transport. */
  readonly inbox: Inbox;
  /**
   * Finds the connection a request belongs to, or `undefined` for an unknown
   * one (a 404). Read it from your own table, keyed by the id in the path.
   */
  readonly connection: (
    id: string,
    request: Request,
  ) => EveInboxConnection | undefined | Promise<EveInboxConnection | undefined>;
  /**
   * The connection id of a request. Default: the last segment of the path, as
   * in `/api/inbox/webhooks/<id>`.
   */
  readonly connectionId?: (request: Request) => string | undefined;
  /** Runs after the event is stored, e.g. `after(() => handoff(args))`. */
  readonly after?: (
    stored: { readonly id: string; readonly duplicate: boolean },
    connection: EveInboxConnection,
  ) => void;
}

const lastSegment = (request: Request): string | undefined => {
  const segments = new URL(request.url).pathname.split("/").filter(Boolean);

  return segments.at(-1);
};

/**
 * A webhook route for one connection per path. It resolves the connection from
 * the path, verifies the request with that connection's own credential (a
 * connection with neither `ref` nor `verify` is refused, never stored) and
 * stores the raw event in the inbox's `inbound_events` for `inboxHandoff`.
 * Without Chat SDK it needs no static adapter per platform.
 */
export function inboxConnectionWebhook(
  options: InboxConnectionWebhookOptions,
): (request: Request) => Promise<Response> {
  return async (request) => {
    const id = (options.connectionId ?? lastSegment)(request);

    if (id === undefined) {
      return new Response("not found", { status: 404 });
    }

    const connection = await options.connection(id, request);

    if (connection === undefined) {
      return new Response("not found", { status: 404 });
    }

    if (connection.ref === undefined && connection.verify === undefined) {
      return new Response("the connection has no credential to verify with", {
        status: 500,
      });
    }

    const handle = webhook({
      inbox: options.inbox,
      adapter: connection.adapter,
      tenant: connection.tenant,
      ...(connection.inboxId === undefined
        ? {}
        : { inboxId: connection.inboxId }),
      ...(connection.credentials === undefined
        ? {}
        : { credentials: connection.credentials }),
      ...(connection.ref === undefined ? {} : { ref: connection.ref }),
      ...(connection.verify === undefined ? {} : { verify: connection.verify }),
      ...(connection.externalId === undefined
        ? {}
        : { externalId: connection.externalId }),
      ...(connection.passthroughHandler === undefined
        ? {}
        : { passthroughHandler: connection.passthroughHandler }),
      ...(options.after === undefined
        ? {}
        : { after: (stored) => options.after?.(stored, connection) }),
    });

    return handle(request);
  };
}

/** What a parser reads out of a stored webhook event. */
export type InboxInboundMessage = Pick<
  InboundInput,
  "threadId" | "contact" | "subject" | "metadata"
> & {
  readonly text: string;
  /** The platform's message id, so a replayed event stores one message. */
  readonly externalId?: string | undefined;
  readonly files?: NonNullable<InboundInput["message"]["files"]>;
};

/** Reads one stored event; `undefined` ignores it (a status callback). */
export type InboxEventParser = (
  event: StoredInboundEvent,
) => InboxInboundMessage | undefined | Promise<InboxInboundMessage | undefined>;

/** Options for `inboxHandoff`. */
export interface InboxHandoffOptions {
  readonly inbox: Inbox;
  /** Parsers by the adapter name the connection's webhook stored. */
  readonly parsers: Readonly<Record<string, InboxEventParser>>;
  /** The eve channel definition that receives each conversation's message. */
  readonly channel: object;
  /**
   * The channel's proactive target for a conversation. Default: `{
   * conversationId }`.
   */
  readonly target?: (conversation: Conversation) => unknown;
  /** Events one run claims. Default 25. */
  readonly limit?: number;
  /** Events that failed this many times are left alone. Default 5. */
  readonly maxAttempts?: number;
}

/** What one `inboxHandoff` run did. */
export interface InboxHandoffResult {
  /** Events whose message was stored (and handed to eve in `bot` mode). */
  readonly processed: number;
  /** Events a parser skipped, or whose adapter has no parser. */
  readonly ignored: number;
  readonly failed: number;
}

/**
 * The session principal for a conversation: the contact in that conversation.
 * The principal id is the conversation id, unlike `routeInbox`, which uses the
 * contact id. The session sync gives a reply handler only the principal's id
 * and type, and a contact can have several conversations, so a contact id could
 * not tell `inboxReplies` which conversation to answer in. The contact id is in
 * the attributes for tools and `inboxRunAs`.
 */
export function inboxPrincipal(conversation: Conversation): EveSessionAuth {
  return {
    authenticator: "inbox",
    principalType: "contact",
    principalId: conversation.id,
    attributes: {
      tenantId: conversation.tenant,
      conversationId: conversation.id,
      contactId: conversation.contactId,
    },
  };
}

/**
 * Hands the inbox's stored webhook events to eve. For each event it stores the
 * message as the contact's (`inbound.record`, so a replay stores one message)
 * and, while the conversation's `bot_mode` is `bot`, sends the text to the eve
 * channel as the contact's principal (`inboxPrincipal`), keyed by the message
 * id so a retry starts no second turn. Pass the result to `waitUntil` after the
 * webhook, or from a schedule.
 */
export function inboxHandoff(
  options: InboxHandoffOptions,
): (args: EveDispatchOptions) => Promise<InboxHandoffResult> {
  const { inbox } = options;

  return async (args) => {
    const events = await inbox.inbound
      .pending({
        limit: options.limit ?? 25,
        maxAttempts: options.maxAttempts ?? 5,
      })
      .orThrow();

    let processed = 0;
    let ignored = 0;
    let failed = 0;

    for (const event of events) {
      const parser = options.parsers[event.adapter];

      if (parser === undefined) {
        await inbox.inbound
          .setStatus({ id: event.id, status: "ignored" })
          .orThrow();
        ignored += 1;
        continue;
      }

      await inbox.inbound
        .setStatus({ id: event.id, status: "processing" })
        .orThrow();

      try {
        const message = await parser(event);

        if (message === undefined) {
          await inbox.inbound
            .setStatus({ id: event.id, status: "ignored" })
            .orThrow();
          ignored += 1;
          continue;
        }

        const inboxId = event.inboxId;

        if (inboxId === null) {
          throw new TypeError(
            "the stored event has no inbox; set inboxId on the connection",
          );
        }

        const recorded = await inbox.inbound
          .record({
            inboxId,
            threadId: message.threadId,
            contact: message.contact,
            message: {
              body: message.text,
              ...(message.externalId === undefined
                ? {}
                : { externalId: message.externalId }),
              ...(message.files === undefined ? {} : { files: message.files }),
            },
            ...(message.subject === undefined
              ? {}
              : { subject: message.subject }),
            ...(message.metadata === undefined
              ? {}
              : { metadata: message.metadata }),
          })
          .orThrow();

        if (!recorded.duplicate) {
          const conversation = await inbox.conversations
            .getConversation(recorded.conversationId)
            .orThrow();

          if (conversation.botMode === "bot") {
            const target = options.target?.(conversation) ?? {
              conversationId: conversation.id,
            };

            // SAFETY: `channel` is an eve channel definition.
            const channel = options.channel as never;
            // SAFETY: `target` is the channel's proactive target.
            const proactive = target as never;

            await args
              .to(channel, proactive)
              .send(message.text, {
                auth: inboxPrincipal(conversation),
                idempotencyKey: recorded.messageId,
                ...(conversation.subject === null
                  ? {}
                  : { title: conversation.subject }),
              });
          }
        }

        await inbox.inbound
          .setStatus({ id: event.id, status: "processed" })
          .orThrow();
        processed += 1;
      } catch (error) {
        await inbox.inbound
          .setStatus({
            id: event.id,
            status: "failed",
            error: errorText(error),
          })
          .orThrow();
        failed += 1;
      }
    }

    return { processed, ignored, failed };
  };
}

/** Options for `inboxRunAs`. */
export interface InboxRunAsOptions {
  /**
   * The service user an inbox session's tools run as: one id, or a function of
   * the conversation's tenant (`undefined` refuses it).
   */
  readonly userId: string | ((tenant: string) => string | undefined);
}

/**
 * The `runAs` option for `supabaseTool` and `eveContext`: a session whose
 * principal came from `inboxPrincipal` runs its tools as the service user, in
 * the conversation's tenant. Any other principal is left to the next rule.
 */
export function inboxRunAs(
  options: InboxRunAsOptions,
): (
  auth: EveSessionAuth | null,
) => { readonly userId: string; readonly tenant: string } | undefined {
  return (auth) => {
    const tenant = auth?.attributes["tenantId"];

    if (
      auth?.authenticator !== "inbox" ||
      typeof tenant !== "string" ||
      tenant === ""
    ) {
      return;
    }

    const userId =
      typeof options.userId === "function"
        ? options.userId(tenant)
        : options.userId;

    return userId === undefined ? undefined : { userId, tenant };
  };
}

/** How `inboxReplies` hands a reply over. */
export type InboxReplyMode = "send" | "draft";

/** Options for `inboxReplies`. */
export interface InboxRepliesOptions {
  /** `createInbox` on a service transport. */
  readonly inbox: Inbox;
  /**
   * `send` writes the reply as a bot message, which the block's deliveries send
   * on the conversation's channel, with provider status callbacks through
   * `deliveries.setStatus`. `draft` stores an `ai` draft that staff review. A
   * function chooses per conversation, such as from the inbox's setting.
   * Default: `send`.
   */
  readonly mode?:
    | InboxReplyMode
    | ((conversation: Conversation) => InboxReplyMode);
}

/**
 * The `reply` handler for `createSessionSync`: each finished reply of an inbox
 * session (see `inboxPrincipal`) goes to its conversation, keyed by the reply's
 * turn, so a replayed pass sends it once. A session with another principal is
 * left alone.
 */
export function inboxReplies(
  options: InboxRepliesOptions,
): (reply: EveSessionReply) => Promise<void> {
  const { inbox } = options;

  return async (reply) => {
    if (reply.principal?.type !== "contact") {
      return;
    }

    const found = await inbox.conversations.getConversation(reply.principal.id);

    if (!found.ok) {
      if (found.error.kind === "not_found") {
        return;
      }

      throw new DbException(found.error);
    }

    const conversation = found.data;

    if (conversation.tenant !== reply.target.organizationId) {
      return;
    }

    const mode =
      typeof options.mode === "function"
        ? options.mode(conversation)
        : (options.mode ?? "send");

    if (mode === "draft") {
      // The inbox keeps one ai draft per `replyKey`, in any status, so a
      // replayed pass returns the draft staff already sent or discarded.
      await inbox.drafts
        .suggest({
          conversationId: conversation.id,
          input: { body: reply.text },
          metadata: { replyKey: reply.key, eveSession: reply.sessionId },
        })
        .orThrow();

      return;
    }

    await inbox.messages
      .send({
        conversationId: conversation.id,
        input: {
          body: reply.text,
          authorType: "bot",
          externalId: `eve:${reply.key}`,
        },
      })
      .orThrow();
  };
}
