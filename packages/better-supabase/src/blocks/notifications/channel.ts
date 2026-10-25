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
  /** The recipient's profile locale, when the profiles block is installed. */
  readonly locale: string | null;
  readonly notification: NotificationItem;
  /**
   * What `render` returned for it in the recipient's locale, when
   * `createNotifications` has one.
   */
  readonly text?: RenderedText;
  /** What `hydrate` returned for the batch, when `createNotifications` has one. */
  readonly hydrated?: unknown;
}

export interface NotificationSendResult {
  /** `skipped` when the channel decided not to send. Defaults to `sent`. */
  readonly status?: "sent" | "skipped";
  /** The provider's name, e.g. `resend` or `fcm`. */
  readonly provider?: string;
  /** The provider's id for the message, kept for support and webhooks. */
  readonly providerMessageId?: string;
  /**
   * The template the message was built from, e.g. `task-assigned-v2`, stored on
   * the delivery for `subjectDeliveries`. Needs notifications module version 6.
   */
  readonly templateKey?: string;
}

/**
 * Sends notifications on one channel (email, push, Slack). The delivery worker
 * (`notifications.deliver()`) claims pending deliveries for the channel's
 * `name` and calls `send` for each. Throwing retries the delivery after its
 * lease, up to `maxAttempts`, then marks it `failed`.
 */
export interface NotificationChannel {
  readonly apiVersion: 1;
  /** Matches the `channel` the deliveries were created for. */
  readonly name: string;
  send(
    message: NotificationMessage,
  ): NotificationSendResult | void | Promise<NotificationSendResult | void>;
}
