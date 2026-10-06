import type { BetterSupabase } from "../../core/define.ts";
import type {
  AnyFunctions,
  AnyModels,
  Row,
  TableKey,
  TableMeta,
} from "../../schema/types.ts";

import { fromBase64, toBase64 } from "../../core/base64.ts";
import { type DbError, dbError } from "../../core/errors.ts";
import { err, ok, type Result } from "../../core/result.ts";
import { temporalMissing } from "../../core/temporal-required.ts";
import { nowInstant, optionalTemporal } from "../../core/temporal.ts";
import { toApp } from "../../plugins/shared.ts";

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
}

export type WebhookInput =
  | Request
  | {
      readonly headers: Headers | Readonly<Record<string, string>>;
      readonly body: string;
    };

const encoder = /* @__PURE__ */ new TextEncoder();

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
const keys = new Map<string, Promise<CryptoKey>>();

function keyFor(secret: string): Promise<CryptoKey> {
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

/** Constant-time string comparison. */
export function timingSafeEqual(a: string, b: string): boolean {
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  let diff = left.length ^ right.length;
  for (let index = 0; index < Math.max(left.length, right.length); index++) {
    diff |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return diff === 0;
}

function header(
  headers: Headers | Readonly<Record<string, string>>,
  name: string,
): string | null {
  if (headers instanceof Headers) return headers.get(name);
  const found = Object.entries(headers).find(
    ([key]) => key.toLowerCase() === name,
  );
  return found?.[1] ?? null;
}

const unauthorized = (code: string, message: string): DbError =>
  dbError("unauthorized", message, { code });

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
  for (const secret of typeof secrets === "string" ? [secrets] : secrets) {
    const key = await keyFor(secret);
    for (const candidate of offered) {
      // crypto.subtle.verify compares HMACs in constant time.
      if (await crypto.subtle.verify("HMAC", key, candidate, content))
        valid = true;
    }
  }
  if (!valid)
    return err(
      unauthorized("WEBHOOK_INVALID_SIGNATURE", "Invalid webhook signature"),
    );

  try {
    // SAFETY: the caller names the payload type T; the signature check above
    // proves the sender, not the shape.
    return ok({
      id,
      timestamp: namespace.Instant.fromEpochMilliseconds(seconds * 1000),
      payload: JSON.parse(body) as T,
      body,
    });
  } catch {
    return err(dbError("invalid_request", "Webhook body is not JSON"));
  }
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

// ---------------------------------------------------------------------------
// Stripe

const toHex = (bytes: Uint8Array): string =>
  Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");

/** Stripe signs with the endpoint secret's UTF-8 bytes, not its base64 decoding. */
async function stripeSignature(
  secret: string,
  content: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return toHex(
    new Uint8Array(
      await crypto.subtle.sign("HMAC", key, encoder.encode(content)),
    ),
  );
}

/** The `Stripe-Signature` header for `body`, for tests and local replays. */
export async function signStripeWebhook(
  secret: string,
  body: string,
  timestamp: Temporal.Instant = nowInstant(),
): Promise<string> {
  const seconds = String(Math.floor(timestamp.epochMilliseconds / 1000));
  return `t=${seconds},v1=${await stripeSignature(secret, `${seconds}.${body}`)}`;
}

/**
 * Verifies a `Stripe-Signature` header (`t=…,v1=…`) with the endpoint's
 * `whsec_…` secret and parses the event. Pass several secrets while rolling
 * the endpoint secret. Runs on WebCrypto, so it needs no `stripe` package.
 */
export async function verifyStripeWebhook<T = unknown>(
  input: WebhookInput,
  secrets: string | readonly string[],
  options: VerifyOptions = {},
): Promise<Result<VerifiedWebhook<T>>> {
  const value = header(input.headers, "stripe-signature");
  if (!value)
    return err(
      unauthorized(
        "WEBHOOK_MISSING_HEADERS",
        "Missing Stripe-Signature header",
      ),
    );
  const parts = value.split(",").map((part) => {
    const index = part.indexOf("=");
    return [part.slice(0, index).trim(), part.slice(index + 1).trim()] as const;
  });
  const timestamp = parts.find(([name]) => name === "t")?.[1] ?? "";
  const offered = parts.filter(([name]) => name === "v1").map(([, sig]) => sig);
  if (!/^\d+$/.test(timestamp))
    return err(
      unauthorized("WEBHOOK_INVALID_TIMESTAMP", "Invalid webhook timestamp"),
    );
  const namespace = optionalTemporal();
  if (namespace === undefined) return err(temporalMissing());
  const seconds = Number(timestamp);
  const now =
    (options.now?.() ?? namespace.Now.instant()).epochMilliseconds / 1000;
  if (Math.abs(now - seconds) > (options.tolerance ?? 300))
    return err(
      unauthorized(
        "WEBHOOK_TIMESTAMP_OUT_OF_RANGE",
        "Webhook timestamp is outside the tolerance",
      ),
    );
  const body = input instanceof Request ? await input.text() : input.body;
  let valid = false;
  for (const secret of typeof secrets === "string" ? [secrets] : secrets) {
    const expected = await stripeSignature(secret, `${timestamp}.${body}`);
    for (const candidate of offered) {
      if (timingSafeEqual(candidate, expected)) valid = true;
    }
  }
  if (!valid)
    return err(
      unauthorized("WEBHOOK_INVALID_SIGNATURE", "Invalid webhook signature"),
    );
  let payload: unknown;
  try {
    payload = JSON.parse(body);
  } catch {
    return err(dbError("invalid_request", "Webhook body is not JSON"));
  }
  const id =
    typeof payload === "object" && payload !== null && "id" in payload
      ? String(payload.id)
      : "";
  // SAFETY: the caller names the event type T; the signature proves the
  // sender, not the shape.
  return ok({
    id,
    timestamp: namespace.Instant.fromEpochMilliseconds(seconds * 1000),
    payload: payload as T,
    body,
  });
}

/**
 * `createInbox({ source: 'stripe', verify: stripeInboxVerify(secret) })`:
 * stores Stripe events keyed by their event id.
 */
export function stripeInboxVerify(
  secrets: string | readonly string[],
  options: VerifyOptions = {},
): (
  request: Request,
  body: string,
) => Promise<Result<{ id: string; payload: unknown }>> {
  return async (request, body) => {
    const verified = await verifyStripeWebhook(
      { headers: request.headers, body },
      secrets,
      options,
    );
    return verified.ok
      ? ok({ id: verified.data.id, payload: verified.data.payload })
      : verified;
  };
}

// ---------------------------------------------------------------------------
// Supabase Auth hooks

interface HookUser {
  readonly id: string;
  readonly email?: string;
  readonly phone?: string;
  readonly app_metadata?: Readonly<Record<string, unknown>>;
  readonly user_metadata?: Readonly<Record<string, unknown>>;
  readonly [key: string]: unknown;
}

export interface AuthHookError {
  readonly error: { readonly http_code: number; readonly message: string };
}

export interface AuthHooks {
  custom_access_token: {
    input: {
      readonly user_id: string;
      readonly claims: Readonly<Record<string, unknown>> & {
        readonly sub: string;
        readonly role: string;
      };
      readonly authentication_method: string;
    };
    output: { readonly claims: Readonly<Record<string, unknown>> };
  };
  send_email: {
    input: {
      readonly user: HookUser;
      readonly email_data: {
        readonly token: string;
        readonly token_hash: string;
        readonly redirect_to: string;
        readonly email_action_type: string;
        readonly site_url: string;
        readonly token_new: string;
        readonly token_hash_new: string;
        /** Auth adds fields over time (`old_email`, `factor_type`, ...). */
        readonly [key: string]: unknown;
      };
    };
    output: Record<never, never>;
  };
  send_sms: {
    input: { readonly user: HookUser; readonly sms: { readonly otp: string } };
    output: Record<never, never>;
  };
  mfa_verification_attempt: {
    input: {
      readonly factor_id: string;
      readonly factor_type: string;
      readonly user_id: string;
      readonly valid: boolean;
    };
    output: {
      readonly decision: "continue" | "reject";
      readonly message?: string;
    };
  };
  password_verification_attempt: {
    input: { readonly user_id: string; readonly valid: boolean };
    output: {
      readonly decision: "continue" | "reject";
      readonly message?: string;
      readonly should_logout_user?: boolean;
    };
  };
  before_user_created: {
    input: {
      readonly metadata: Readonly<Record<string, unknown>>;
      readonly user: HookUser;
    };
    output: Record<never, never>;
  };
}

export type AuthHookKind = keyof AuthHooks;

/** Rejects a hook with a status and message Supabase Auth passes to the client. */
export function hookError(status: number, message: string): AuthHookError {
  return { error: { http_code: status, message } };
}

/**
 * A `(request) => Response` handler for a Supabase Auth hook: verifies the
 * Standard Webhooks signature, types the payload and serializes the answer.
 *
 * ```ts
 * export const POST = authHook('custom_access_token', env.AUTH_HOOK_SECRET, async ({ claims, user_id }) => ({
 *   claims: { ...claims, tenant_id: await organizationFor(user_id) },
 * }));
 * ```
 */
export function authHook<K extends AuthHookKind>(
  _kind: K,
  secret: string | readonly string[],
  handler: (
    payload: AuthHooks[K]["input"],
    webhook: VerifiedWebhook<AuthHooks[K]["input"]>,
  ) =>
    | AuthHooks[K]["output"]
    | AuthHookError
    | Promise<AuthHooks[K]["output"] | AuthHookError>,
  options?: VerifyOptions,
): (request: Request) => Promise<Response> {
  return async (request) => {
    const verified = await verifyWebhook<AuthHooks[K]["input"]>(
      request,
      secret,
      options,
    );
    if (!verified.ok)
      return Response.json(
        hookError(verified.error.status, verified.error.message),
        { status: verified.error.status },
      );
    try {
      const answer = await handler(verified.data.payload, verified.data);
      const status = "error" in answer ? answer.error.http_code : 200;
      return Response.json(answer, { status });
    } catch (cause) {
      console.error("better-supabase: auth hook failed", cause);
      return Response.json(hookError(500, "Hook failed"), { status: 500 });
    }
  };
}

// ---------------------------------------------------------------------------
// Database webhooks (pg_net / Supabase dashboard)

export interface DatabaseWebhookPayload {
  readonly type: "INSERT" | "UPDATE" | "DELETE";
  readonly table: string;
  readonly schema: string;
  readonly record: Readonly<Record<string, unknown>> | null;
  readonly old_record: Readonly<Record<string, unknown>> | null;
}

export interface DatabaseChange<R> {
  readonly type: "INSERT" | "UPDATE" | "DELETE";
  readonly table: string;
  readonly record: R | null;
  readonly oldRecord: Partial<R> | null;
}

export function isDatabaseWebhook(
  value: unknown,
): value is DatabaseWebhookPayload {
  if (typeof value !== "object" || value === null) return false;
  // SAFETY: the check above narrows value to a non-null object, and each field
  // is checked below.
  const payload = value as Record<string, unknown>;
  return (
    (payload["type"] === "INSERT" ||
      payload["type"] === "UPDATE" ||
      payload["type"] === "DELETE") &&
    typeof payload["table"] === "string" &&
    typeof payload["schema"] === "string"
  );
}

/**
 * Reads a database webhook payload for `table` as an app-cased change.
 * Returns `null` for other tables or payloads that aren't database webhooks.
 */
export function databaseChange<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  T extends TableKey<M>,
>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  table: T,
  payload: unknown,
): DatabaseChange<Row<M, T>> | null {
  const meta: TableMeta | undefined = betterSupabase.meta.tables[table];
  if (
    !meta ||
    !isDatabaseWebhook(payload) ||
    payload.table !== meta.name ||
    payload.schema !== meta.schema
  )
    return null;
  return {
    type: payload.type,
    table,
    record: payload.record ? toApp(meta, payload.record) : null,
    oldRecord: payload.old_record ? toApp(meta, payload.old_record) : null,
  };
}
