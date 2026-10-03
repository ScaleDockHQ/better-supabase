import type { NotificationItem, RenderedText } from "./types.ts";

/** One pending delivery a channel sends: the notification and who gets it. */
export interface NotificationMessage {
  readonly deliveryId: string;
  /** The channel name, e.g. `email`. */
  readonly channel: string;
  /** 1 on the first try. */
  readonly attempts: number;
  readonly userId: string;
  /** The recipient's `auth.users` email, for email channels. */
  readonly email: string | null;
  readonly notification: NotificationItem;
  /** What `render` returned for it, when `createNotifications` has one. */
  readonly text?: RenderedText;
}

export interface NotificationSendResult {
  /** `skipped` when the channel decided not to send. Defaults to `sent`. */
  readonly status?: "sent" | "skipped";
  /** The provider's name, e.g. `resend` or `fcm`. */
  readonly provider?: string;
  /** The provider's id for the message, kept for support and webhooks. */
  readonly providerMessageId?: string;
}

/**
 * Sends notifications on one channel (email, push, Slack). The delivery
 * worker (`notifications.deliver()`) claims pending deliveries for the
 * channel's `name` and calls `send` for each. Throwing retries the delivery
 * after its lease, up to `maxAttempts`, then marks it `failed`.
 */
export interface NotificationChannel {
  readonly apiVersion: 1;
  /** Matches the `channel` the deliveries were created for. */
  readonly name: string;
  send(
    message: NotificationMessage,
  ): NotificationSendResult | void | Promise<NotificationSendResult | void>;
}
