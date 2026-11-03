import type { Inbox } from "../blocks/inbox/inbox.ts";
import type { ChatInboundStore } from "./store.ts";

import { whatsappWindowOpen } from "./channels.ts";

/** An approved WhatsApp message template, as `@chat-adapter/whatsapp` sends it. */
export interface WhatsappTemplate {
  readonly name: string;
  /** The template's language code, such as `en_US`. */
  readonly language: string;
  /** Header, body and button parameters, in the Cloud API's `components` shape. */
  readonly components?: readonly Record<string, unknown>[];
}

/**
 * The part of `@chat-adapter/whatsapp`'s adapter that sends a template. It is
 * typed structurally, so the package stays an optional peer.
 */
export interface WhatsappTemplateAdapter {
  sendTemplate(threadId: string, template: WhatsappTemplate): Promise<unknown>;
}

/** A Chat SDK thread, as `sendWithinWindowOrTemplate` uses it. */
export interface WindowedThread<M> {
  readonly id: string;
  readonly adapter: unknown;
  post(message: M): Promise<unknown>;
}

export interface SendWithinWindowOptions {
  /** `createInbox` on a service transport, or a `ChatInboundStore`. */
  readonly inbox: Inbox | ChatInboundStore;
  /** The conversation whose last inbound message opens the window. */
  readonly conversationId: string;
  /** Sent in place of the message once the 24-hour window has closed. */
  readonly template?: WhatsappTemplate;
  readonly now?: Temporal.Instant;
}

/** Thrown when the window is closed and no template can be sent. */
export class ChatWindowClosedError extends Error {
  readonly code = "CHAT_WINDOW_CLOSED";
  readonly conversationId: string;

  constructor(conversationId: string, reason: string) {
    super(
      `The WhatsApp reply window of conversation ${conversationId} is closed: ${reason}`,
    );
    this.name = "ChatWindowClosedError";
    this.conversationId = conversationId;
  }
}

const hasSendTemplate = (value: unknown): value is WhatsappTemplateAdapter =>
  typeof value === "object" &&
  value !== null &&
  "sendTemplate" in value &&
  typeof value.sendTemplate === "function";

/**
 * Posts `message` while the contact's 24-hour window is open (it reads
 * `conversations.last_inbound_at`), and the approved `template` through the
 * adapter's `sendTemplate` once it has closed. A closed window with no
 * template, or an adapter without `sendTemplate`, throws a
 * `ChatWindowClosedError` (`code: "CHAT_WINDOW_CLOSED"`) instead of letting
 * WhatsApp reject the post.
 */
export async function sendWithinWindowOrTemplate<M>(
  thread: WindowedThread<M>,
  message: M,
  options: SendWithinWindowOptions,
): Promise<{ readonly sent: "message" | "template"; readonly raw: unknown }> {
  const open = await whatsappWindowOpen(
    options.inbox,
    options.conversationId,
    options.now,
  );

  if (open) {
    return { sent: "message", raw: await thread.post(message) };
  }

  if (options.template === undefined) {
    throw new ChatWindowClosedError(
      options.conversationId,
      "send an approved template",
    );
  }

  if (!hasSendTemplate(thread.adapter)) {
    throw new ChatWindowClosedError(
      options.conversationId,
      "the adapter cannot send a template",
    );
  }

  return {
    sent: "template",
    raw: await thread.adapter.sendTemplate(thread.id, options.template),
  };
}
