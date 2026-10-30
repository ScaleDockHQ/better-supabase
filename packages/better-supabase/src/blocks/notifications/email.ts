import type {
  ContactMessage,
  NotificationChannel,
  NotificationMessage,
  NotificationSendResult,
} from "./channel.ts";
import type {
  DeliveryTransport,
  MailCategory,
  UnsubscribeTarget,
} from "./delivery.ts";
import type { RenderedText } from "./types.ts";

import { mailHeaders } from "./delivery.ts";

/** The mail for one delivery. */
export interface ComposedEmail {
  readonly subject: string;
  readonly text?: string;
  readonly html?: string;
  readonly replyTo?: string;
  /** Defaults to `notification`. */
  readonly category?: MailCategory;
  /**
   * Names the template this mail came from, e.g. `task-assigned-v2`. The
   * delivery keeps it, so a record's sent emails show which one went out.
   */
  readonly templateKey?: string;
}

export interface EmailChannelOptions {
  readonly transport: DeliveryTransport;
  /** `Name <address>` or an address the provider has verified. */
  readonly from: string;
  readonly replyTo?: string;
  /**
   * The mail for a delivery. Defaults to the rendered title as the subject and
   * the rendered body (or the title) as the text, so it needs
   * `createNotifications({ render })`.
   */
  readonly compose?: (
    message: NotificationMessage,
  ) => ComposedEmail | Promise<ComposedEmail>;
  /**
   * The mail for a `{ email, name }` recipient of `send`. Defaults to the same
   * subject and text as `compose`'s default.
   */
  readonly composeContact?: (
    message: ContactMessage,
  ) => ComposedEmail | Promise<ComposedEmail>;
  /**
   * Where the reader unsubscribes from this mail, such as a signed link to your
   * preferences route. Only `notification` mail carries it.
   */
  readonly unsubscribe?: (
    message: NotificationMessage,
  ) => UnsubscribeTarget | undefined | Promise<UnsubscribeTarget | undefined>;
}

function defaultCompose(message: {
  readonly text?: RenderedText;
}): ComposedEmail {
  const text = message.text;

  if (text === undefined) {
    throw new TypeError(
      "The email channel needs createNotifications({ render }) or a compose option",
    );
  }

  return { subject: text.title, text: text.body ?? text.title };
}

/**
 * A `"Name" <address>` mailbox, without quotes, backslashes or line breaks in
 * the name.
 */
function mailbox(contact: ContactMessage["contact"]): string {
  const name = contact.name?.replaceAll(/["\\\r\n]/g, "").trim();

  return name === undefined || name === ""
    ? contact.email
    : `"${name}" <${contact.email}>`;
}

/**
 * A `NotificationChannel` named `email` that sends through `transport`, with
 * the delivery id as the idempotency key. A recipient without an address is
 * skipped. It also sends to the `{ email, name }` recipients of `send`, keyed
 * by the event id and the address, without an unsubscribe header.
 */
export function emailChannel(
  options: EmailChannelOptions,
): NotificationChannel {
  const { transport } = options;
  const version: unknown = transport.apiVersion;
  const channel: unknown = transport.channel;

  if (version !== 1 || channel !== "email") {
    throw new TypeError(
      `emailChannel needs an email DeliveryTransport with apiVersion 1, got channel "${String(channel)}"`,
    );
  }

  const compose = options.compose ?? defaultCompose;
  const composeContact = options.composeContact ?? defaultCompose;

  const deliver = async (
    mail: ComposedEmail,
    to: string,
    idempotencyKey: string,
    unsubscribe: (() => Promise<UnsubscribeTarget | undefined>) | undefined,
  ): Promise<NotificationSendResult> => {
    const category = mail.category ?? "notification";

    const target =
      category === "notification" ? await unsubscribe?.() : undefined;

    const replyTo = mail.replyTo ?? options.replyTo;

    const receipt = await transport.send(
      {
        from: options.from,
        to,
        subject: mail.subject,
        ...(mail.text === undefined ? {} : { text: mail.text }),
        ...(mail.html === undefined ? {} : { html: mail.html }),
        ...(replyTo === undefined ? {} : { replyTo }),
        category,
        headers: mailHeaders(category, target),
      },
      { idempotencyKey },
    );

    return {
      provider: transport.provider,
      ...(receipt?.providerMessageId === undefined
        ? {}
        : { providerMessageId: receipt.providerMessageId }),
      ...(mail.templateKey === undefined
        ? {}
        : { templateKey: mail.templateKey }),
    };
  };

  return {
    apiVersion: 1,
    name: "email",
    async send(message): Promise<NotificationSendResult> {
      if (message.email === null || message.email === "") {
        return { status: "skipped", provider: transport.provider };
      }

      const { unsubscribe } = options;

      return deliver(
        await compose(message),
        message.email,
        message.deliveryId,
        unsubscribe === undefined
          ? undefined
          : async () => unsubscribe(message),
      );
    },
    async sendToContact(message): Promise<NotificationSendResult> {
      return deliver(
        await composeContact(message),
        mailbox(message.contact),
        message.key,
        undefined,
      );
    },
  };
}
