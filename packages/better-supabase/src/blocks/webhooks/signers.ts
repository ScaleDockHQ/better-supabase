import { toBase64 } from "../../core/base64.ts";
import { signWebhook } from "./verify.ts";

export interface WebhookSignInput {
  /** The delivery id, the same on every retry so receivers can deduplicate. */
  readonly id: string;
  readonly body: string;
  readonly timestamp: Temporal.Instant;
  /** The endpoint's live secrets, newest first. Sign with each while rotating. */
  readonly secrets: readonly string[];
}

/**
 * Adds the signature headers to an outgoing webhook. `standardWebhooks()`
 * is the default; `hmacSigner()` covers custom header and payload formats.
 */
export interface WebhookSigner {
  readonly apiVersion: 1;
  readonly name: string;
  sign(
    input: WebhookSignInput,
  ):
    | Readonly<Record<string, string>>
    | Promise<Readonly<Record<string, string>>>;
}

export interface StandardWebhooksOptions {
  /** Header names, for receivers that expect a prefix such as `svix-`. */
  readonly headers?: {
    readonly id?: string;
    readonly timestamp?: string;
    readonly signature?: string;
  };
}

function needSecrets(secrets: readonly string[]): void {
  if (secrets.length === 0)
    throw new TypeError("The endpoint has no signing secret");
}

/**
 * Signs with the [Standard Webhooks](https://www.standardwebhooks.com/)
 * scheme: `webhook-id`, `webhook-timestamp` and one `v1,` signature per
 * secret in `webhook-signature`. `verifyWebhook` checks it.
 */
export function standardWebhooks(
  options: StandardWebhooksOptions = {},
): WebhookSigner {
  const names = {
    id: options.headers?.id ?? "webhook-id",
    timestamp: options.headers?.timestamp ?? "webhook-timestamp",
    signature: options.headers?.signature ?? "webhook-signature",
  };
  return {
    apiVersion: 1,
    name: "standard-webhooks",
    async sign({ id, body, timestamp, secrets }) {
      needSecrets(secrets);
      const signed = await Promise.all(
        secrets.map((secret) => signWebhook(secret, { id, body, timestamp })),
      );
      return {
        [names.id]: id,
        [names.timestamp]: signed[0]!["webhook-timestamp"]!,
        [names.signature]: signed
          .map((headers) => headers["webhook-signature"])
          .join(" "),
      };
    },
  };
}

export interface HmacSignerOptions {
  readonly name?: string;
  /** e.g. `x-acme-signature`. */
  readonly signatureHeader: string;
  /** Sends the epoch-seconds timestamp in this header. */
  readonly timestampHeader?: string;
  /** Sends the delivery id in this header. */
  readonly idHeader?: string;
  /** The signed text. Defaults to `${timestamp}.${body}`. */
  readonly content?: (input: {
    readonly id: string;
    readonly timestamp: string;
    readonly body: string;
  }) => string;
  /** Defaults to `hex`. */
  readonly encoding?: "hex" | "base64";
  /** Written before each signature. Defaults to `v1=`. */
  readonly prefix?: string;
  /** Joins the signatures of several secrets. Defaults to `,`. */
  readonly separator?: string;
}

const encoder = /* @__PURE__ */ new TextEncoder();

const hex = (bytes: Uint8Array): string =>
  Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");

/**
 * HMAC-SHA256 with the secret's UTF-8 bytes as the key, for receivers that
 * verify an existing format, e.g. `v1=<hex>` over `timestamp.body`.
 */
export function hmacSigner(options: HmacSignerOptions): WebhookSigner {
  const content =
    options.content ??
    ((input: { timestamp: string; body: string }) =>
      `${input.timestamp}.${input.body}`);
  const encode = options.encoding === "base64" ? toBase64 : hex;
  const prefix = options.prefix ?? "v1=";
  return {
    apiVersion: 1,
    name: options.name ?? "hmac",
    async sign({ id, body, timestamp, secrets }) {
      needSecrets(secrets);
      const seconds = String(Math.floor(timestamp.epochMilliseconds / 1000));
      const message = encoder.encode(content({ id, timestamp: seconds, body }));
      const signatures = await Promise.all(
        secrets.map(async (secret) => {
          const key = await crypto.subtle.importKey(
            "raw",
            encoder.encode(secret),
            { name: "HMAC", hash: "SHA-256" },
            false,
            ["sign"],
          );
          const mac = await crypto.subtle.sign("HMAC", key, message);
          return `${prefix}${encode(new Uint8Array(mac))}`;
        }),
      );
      return {
        [options.signatureHeader]: signatures.join(options.separator ?? ","),
        ...(options.timestampHeader
          ? { [options.timestampHeader]: seconds }
          : {}),
        ...(options.idHeader ? { [options.idHeader]: id } : {}),
      };
    },
  };
}
