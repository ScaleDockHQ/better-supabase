import type {
  NotificationChannel,
  NotificationMessage,
  NotificationSendResult,
} from "./channel.ts";

import {
  type DeliveryTransport,
  type MailCategory,
  mailHeaders,
  type UnsubscribeTarget,
} from "./delivery.ts";

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
   * The mail for a delivery. Defaults to the rendered title as the subject
   * and the rendered body (or the title) as the text, so it needs
   * `createNotifications({ render })`.
   */
  readonly compose?: (
    message: NotificationMessage,
  ) => ComposedEmail | Promise<ComposedEmail>;
  /**
   * Where the reader unsubscribes from this mail, such as a signed link to
   * your preferences route. Only `notification` mail carries it.
   */
  readonly unsubscribe?: (
    message: NotificationMessage,
  ) => UnsubscribeTarget | undefined | Promise<UnsubscribeTarget | undefined>;
}

function defaultCompose(message: NotificationMessage): ComposedEmail {
  const text = message.text;
  if (text === undefined) {
    throw new TypeError(
      "The email channel needs createNotifications({ render }) or a compose option",
    );
  }
  return { subject: text.title, text: text.body ?? text.title };
}

/**
 * A `NotificationChannel` named `email` that sends through `transport`,
 * with the delivery id as the idempotency key. A recipient without an
 * address is skipped.
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
  return {
    apiVersion: 1,
    name: "email",
    async send(message): Promise<NotificationSendResult> {
      if (message.email === null || message.email === "") {
        return { status: "skipped", provider: transport.provider };
      }
      const mail = await compose(message);
      const category = mail.category ?? "notification";
      const unsubscribe =
        category === "notification"
          ? await options.unsubscribe?.(message)
          : undefined;
      const replyTo = mail.replyTo ?? options.replyTo;
      const receipt = await transport.send(
        {
          from: options.from,
          to: message.email,
          subject: mail.subject,
          ...(mail.text === undefined ? {} : { text: mail.text }),
          ...(mail.html === undefined ? {} : { html: mail.html }),
          ...(replyTo === undefined ? {} : { replyTo }),
          category,
          headers: mailHeaders(category, unsubscribe),
        },
        { idempotencyKey: message.deliveryId },
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
    },
  };
}
