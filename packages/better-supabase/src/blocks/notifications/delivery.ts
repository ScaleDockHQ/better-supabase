/**
 * What a message is for. `security` (sign-in codes, password resets, new-device
 * alerts) and `approval` (a request waiting on the reader) mail never carries
 * an unsubscribe link: the reader can't opt out of it.
 */
export type MailCategory = "notification" | "security" | "approval";

/** One email, ready for a provider. */
export interface EmailMessage {
  readonly from: string;
  readonly to: string;
  readonly subject: string;
  readonly text?: string;
  readonly html?: string;
  readonly replyTo?: string;
  readonly category: MailCategory;
  /**
   * Headers the provider sends as given: `Auto-Submitted` on every message, and
   * `List-Unsubscribe` with `List-Unsubscribe-Post` on notification mail that
   * has an unsubscribe address.
   */
  readonly headers: Readonly<Record<string, string>>;
}

/** The message each channel's transport sends. */
export interface DeliveryMessages {
  readonly email: EmailMessage;
}

export type DeliveryChannel = keyof DeliveryMessages;

export interface DeliverySendOptions {
  /**
   * The delivery id. A provider that dedupes by key sends a retried delivery
   * once; pass it as the provider's idempotency key.
   */
  readonly idempotencyKey: string;
}

export interface DeliveryReceipt {
  /** The provider's id for the message, kept for support and webhooks. */
  readonly providerMessageId?: string;
}

/**
 * Sends one message through a provider (Resend, Postmark, SES, SMTP). A throw
 * retries the delivery after its lease, with the same idempotency key.
 */
export interface DeliveryTransport<
  C extends DeliveryChannel = DeliveryChannel,
> {
  readonly apiVersion: 1;
  readonly channel: C;
  /** Stored on the delivery, e.g. `resend`. */
  readonly provider: string;
  send(
    message: DeliveryMessages[C],
    options: DeliverySendOptions,
  ): DeliveryReceipt | void | Promise<DeliveryReceipt | void>;
}

/**
 * Where a reader unsubscribes: an `https:` URL for one-click, a `mailto:`
 * address, or both.
 */
export interface UnsubscribeTarget {
  /** Receives the RFC 8058 one-click `POST`; must be `https:`. */
  readonly url?: string;
  /** `mailto:` address, with an optional `?subject=`. */
  readonly mailto?: string;
}

/**
 * The headers automated mail carries: `Auto-Submitted: auto-generated` (RFC 3834)
 * on every message, so auto-responders stay quiet, and on `notification` mail
 * with an unsubscribe target, `List-Unsubscribe` (RFC 2369).
 * `List-Unsubscribe-Post: List-Unsubscribe=One-Click` (RFC 8058) needs the
 * `https:` URL, so a `mailto:`-only target leaves it out. Throws a `TypeError`
 * for a URL that isn't `https:` or an address that isn't `mailto:`.
 */
export function mailHeaders(
  category: MailCategory,
  unsubscribe?: UnsubscribeTarget,
): Record<string, string> {
  const headers: Record<string, string> = {
    "Auto-Submitted": "auto-generated",
  };

  if (category !== "notification" || unsubscribe === undefined) {
    return headers;
  }

  const targets: string[] = [];

  if (unsubscribe.url !== undefined) {
    if (!URL.canParse(unsubscribe.url)) {
      throw new TypeError(
        `The unsubscribe URL "${unsubscribe.url}" is not a URL`,
      );
    }

    if (new URL(unsubscribe.url).protocol !== "https:") {
      throw new TypeError(
        `The unsubscribe URL "${unsubscribe.url}" must use https (RFC 8058)`,
      );
    }

    targets.push(`<${unsubscribe.url}>`);
  }

  if (unsubscribe.mailto !== undefined) {
    if (!/^mailto:[^\s<>]+$/i.test(unsubscribe.mailto)) {
      throw new TypeError(
        `The unsubscribe address "${unsubscribe.mailto}" must be a mailto: URI`,
      );
    }

    targets.push(`<${unsubscribe.mailto}>`);
  }

  if (targets.length === 0) {
    return headers;
  }

  headers["List-Unsubscribe"] = targets.join(", ");

  if (unsubscribe.url !== undefined) {
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click";
  }

  return headers;
}
