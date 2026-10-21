import type {
  DeliveryReceipt,
  DeliveryTransport,
  EmailMessage,
} from "../delivery.ts";

import { isRecord } from "../../shared.ts";

export interface ResendTransportOptions {
  /**
   * A Resend API key with sending access. Read it from your own env; the
   * library never does.
   */
  readonly apiKey: string;
  /** Defaults to `https://api.resend.com`. */
  readonly baseUrl?: string;
  /** Defaults to the global `fetch`. */
  readonly fetch?: typeof fetch;
}

/**
 * A failed Resend call. `status` is the HTTP status, 0 when the request never
 * got an answer.
 */
export class ResendError extends Error {
  readonly status: number;
  /** Resend's error name, such as `validation_error`. */
  readonly code: string | undefined;

  constructor(status: number, message: string, code?: string) {
    super(message);
    this.name = "ResendError";
    this.status = status;
    this.code = code;
  }
}

/**
 * A `DeliveryTransport` over Resend's `POST /emails`. The delivery id goes in
 * the `Idempotency-Key` header, so a retried delivery sends one email; the
 * message category becomes a `category` tag.
 */
export function resendTransport(
  options: ResendTransportOptions,
): DeliveryTransport {
  if (options.apiKey === "") {
    throw new TypeError("resendTransport needs an apiKey");
  }

  const endpoint = `${(options.baseUrl ?? "https://api.resend.com").replace(/\/+$/, "")}/emails`;
  const send = options.fetch ?? fetch;

  return {
    apiVersion: 1,
    channel: "email",
    provider: "resend",
    async send(
      message: EmailMessage,
      { idempotencyKey },
    ): Promise<DeliveryReceipt> {
      const response = await send(endpoint, {
        method: "POST",
        redirect: "error",
        headers: {
          authorization: `Bearer ${options.apiKey}`,
          "content-type": "application/json",
          "idempotency-key": idempotencyKey,
        },
        body: JSON.stringify({
          from: message.from,
          to: [message.to],
          subject: message.subject,
          ...(message.text === undefined ? {} : { text: message.text }),
          ...(message.html === undefined ? {} : { html: message.html }),
          ...(message.replyTo === undefined
            ? {}
            : { reply_to: message.replyTo }),
          headers: message.headers,
          tags: [{ name: "category", value: message.category }],
        }),
      }).catch((cause: unknown) => {
        throw new ResendError(
          0,
          `Resend did not answer: ${cause instanceof Error ? cause.message : String(cause)}`,
        );
      });

      const body: unknown = await response.json().catch(() => undefined);

      if (!response.ok) {
        const text =
          isRecord(body) && typeof body["message"] === "string"
            ? body["message"]
            : response.statusText;

        throw new ResendError(
          response.status,
          `Resend answered ${String(response.status)}: ${text}`,
          isRecord(body) && typeof body["name"] === "string"
            ? body["name"]
            : undefined,
        );
      }

      return isRecord(body) && typeof body["id"] === "string"
        ? { providerMessageId: body["id"] }
        : {};
    },
  };
}
