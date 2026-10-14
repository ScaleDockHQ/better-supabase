import { fromBase64, toBase64 } from "./base64.ts";
import { type DbError, dbError } from "./errors.ts";
import { encoder, timingSafeEqual } from "./hmac.ts";
import { err, ok, type Result } from "./result.ts";
import { temporalMissing } from "./temporal-required.ts";
import { nowInstant, optionalTemporal } from "./temporal.ts";

export { hmacHex, timingSafeEqual } from "./hmac.ts";

// ---------------------------------------------------------------------------
// Standard Webhooks

export interface VerifiedWebhook<T = unknown> {
  readonly id: string;
  readonly timestamp: Temporal.Instant;
  readonly payload: T;
  readonly body: string;
}

export interface VerifyOptions {
  /** Allowed clock skew in seconds. Defaults to 300. */
  readonly tolerance?: number;
  readonly now?: () => Temporal.Instant;
  /**
   * Records a verified `webhook-id` and answers whether it was already
   * recorded, atomically (a unique insert, Redis `SET NX`). A seen id is
   * refused as a replay (`WEBHOOK_REPLAYED`, 409). `until` is when the
   * timestamp leaves the tolerance window, so the store may forget the id
   * after it. Runs only after the signature checks out, and a throw
   * refuses the request.
   */
  readonly seen?: (
    id: string,
    until: Temporal.Instant,
  ) => boolean | Promise<boolean>;
}

export type WebhookInput =
  | Request
  | {
      readonly headers: Headers | Readonly<Record<string, string>>;
      readonly body: string;
    };

/** Accepts `whsec_…`, `v1,whsec_…` (Supabase Auth hooks) or raw base64. */
function secretBytes(secret: string): Uint8Array<ArrayBuffer> {
  const raw = secret.replace(/^v1,/, "").replace(/^whsec_/, "");
  try {
    return fromBase64(raw);
  } catch {
    throw new TypeError("Webhook secret is not valid base64");
  }
}

/** Secrets come from configuration, so a handful of keys suffice. */
// Typed from `crypto.subtle`, because `CryptoKey` is a value only under @types/node without the DOM lib.
type ImportedKey = ReturnType<typeof crypto.subtle.importKey>;
const keys = new Map<string, ImportedKey>();

function keyFor(secret: string): ImportedKey {
  let key = keys.get(secret);
  if (!key) {
    key = crypto.subtle.importKey(
      "raw",
      secretBytes(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign", "verify"],
    );
    if (keys.size < 16) {
      keys.set(secret, key);
      key.catch(() => keys.delete(secret));
    }
  }
  return key;
}

async function signature(secret: string, content: string): Promise<string> {
  return toBase64(
    new Uint8Array(
      await crypto.subtle.sign(
        "HMAC",
        await keyFor(secret),
        encoder.encode(content),
      ),
    ),
  );
}

function decodeSignature(value: string): Uint8Array<ArrayBuffer> | undefined {
  try {
    return fromBase64(value);
  } catch {
    return undefined;
  }
}

export function header(
  headers: Headers | Readonly<Record<string, string>>,
  name: string,
): string | null {
  if (headers instanceof Headers) return headers.get(name);
  const found = Object.entries(headers).find(
    ([key]) => key.toLowerCase() === name,
  );
  return found?.[1] ?? null;
}

export const unauthorized = (code: string, message: string): DbError =>
  dbError("unauthorized", message, { code });

/**
 * The error for a webhook id `options.seen` already recorded, or for a
 * `seen` that throws; `undefined` for a first delivery or without `seen`.
 */
export async function replayed(
  options: VerifyOptions,
  id: string,
  until: Temporal.Instant,
): Promise<DbError | undefined> {
  if (!options.seen || id === "") return undefined;
  try {
    if (!(await options.seen(id, until))) return undefined;
  } catch {
    return dbError(
      "unexpected",
      "Could not check the webhook id for a replay",
      {
        code: "WEBHOOK_DEDUPE_FAILED",
      },
    );
  }
  return dbError("conflict", "Webhook was already received", {
    code: "WEBHOOK_REPLAYED",
  });
}

/** Headers for a signed Standard Webhooks request. */
export async function signWebhook(
  secret: string,
  message: {
    readonly id: string;
    readonly body: string;
    readonly timestamp?: Temporal.Instant;
  },
): Promise<Record<string, string>> {
  // Standard Webhooks carry the timestamp as epoch seconds.
  const timestamp = String(
    Math.floor((message.timestamp ?? nowInstant()).epochMilliseconds / 1000),
  );
  return {
    "webhook-id": message.id,
    "webhook-timestamp": timestamp,
    "webhook-signature": `v1,${await signature(secret, `${message.id}.${timestamp}.${message.body}`)}`,
  };
}

/**
 * Verifies a Standard Webhooks signature (`webhook-id`, `webhook-timestamp`,
 * `webhook-signature`, or the `svix-` names Svix-based senders use) and
 * parses the JSON body. Pass several secrets while rotating.
 */
export async function verifyWebhook<T = unknown>(
  input: WebhookInput,
  secrets: string | readonly string[],
  options: VerifyOptions = {},
): Promise<Result<VerifiedWebhook<T>>> {
  const headers = input.headers;
  const prefix = header(headers, "webhook-id") === null ? "svix" : "webhook";
  const id = header(headers, `${prefix}-id`);
  const timestamp = header(headers, `${prefix}-timestamp`);
  const signatures = header(headers, `${prefix}-signature`);
  if (!id || !timestamp || !signatures)
    return err(
      unauthorized(
        "WEBHOOK_MISSING_HEADERS",
        "Missing webhook signature headers",
      ),
    );
  const seconds = Number(timestamp);
  if (!/^\d+$/.test(timestamp))
    return err(
      unauthorized("WEBHOOK_INVALID_TIMESTAMP", "Invalid webhook timestamp"),
    );
  const namespace = optionalTemporal();
  if (namespace === undefined) return err(temporalMissing());
  const now =
    (options.now?.() ?? namespace.Now.instant()).epochMilliseconds / 1000;
  const tolerance = options.tolerance ?? 300;
  if (seconds < now - tolerance)
    return err(
      unauthorized("WEBHOOK_TIMESTAMP_TOO_OLD", "Webhook timestamp is too old"),
    );
  if (seconds > now + tolerance)
    return err(
      unauthorized(
        "WEBHOOK_TIMESTAMP_TOO_NEW",
        "Webhook timestamp is in the future",
      ),
    );

  const body = input instanceof Request ? await input.text() : input.body;
  const content = encoder.encode(`${id}.${timestamp}.${body}`);
  const offered = signatures
    .split(" ")
    .map((entry) => entry.split(","))
    .filter(([version, value]) => version === "v1" && value)
    .flatMap(([, value]) => decodeSignature(value!) ?? []);
  let valid = false;
  let malformed = false;
  for (const secret of typeof secrets === "string" ? [secrets] : secrets) {
    let key: Awaited<ImportedKey>;
    try {
      key = await keyFor(secret);
    } catch {
      malformed = true;
      continue;
    }
    for (const candidate of offered) {
      // crypto.subtle.verify compares HMACs in constant time.
      if (await crypto.subtle.verify("HMAC", key, candidate, content))
        valid = true;
    }
  }
  if (!valid && malformed)
    return err(
      dbError("unexpected", "Webhook secret is not whsec_ followed by base64", {
        code: "WEBHOOK_INVALID_SECRET",
      }),
    );
  if (!valid)
    return err(
      unauthorized("WEBHOOK_INVALID_SIGNATURE", "Invalid webhook signature"),
    );

  let payload: T;
  try {
    // SAFETY: the caller names the payload type T; the signature check above
    // proves the sender, not the shape.
    payload = JSON.parse(body) as T;
  } catch {
    return err(dbError("invalid_request", "Webhook body is not JSON"));
  }
  const replay = await replayed(
    options,
    id,
    namespace.Instant.fromEpochMilliseconds((seconds + tolerance) * 1000),
  );
  if (replay) return err(replay);
  return ok({
    id,
    timestamp: namespace.Instant.fromEpochMilliseconds(seconds * 1000),
    payload,
    body,
  });
}

/** Checks a shared-secret header (database webhooks), in constant time. */
export function verifySharedSecret(
  request: Request,
  secret: string,
  headerName = "authorization",
): boolean {
  const value = request.headers.get(headerName) ?? "";
  const token = value.replace(/^Bearer\s+/i, "");
  return timingSafeEqual(token, secret);
}
