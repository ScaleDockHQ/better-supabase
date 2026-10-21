import type { BetterSupabase } from "../../core/define.ts";
import type { Result } from "../../core/result.ts";
import type {
  VerifiedWebhook,
  VerifyOptions,
  WebhookInput,
} from "../../core/signatures.ts";
import type {
  AnyFunctions,
  AnyModels,
  Row,
  TableKey,
  TableMeta,
} from "../../schema/types.ts";

import { dbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";
import {
  header,
  hmacHex,
  replayed,
  unauthorized,
  timingSafeEqual,
  verifyWebhook,
} from "../../core/signatures.ts";
import { temporalMissing } from "../../core/temporal-required.ts";
import { nowInstant, optionalTemporal } from "../../core/temporal.ts";
import { toApp } from "../../schema/casing.ts";

export {
  signWebhook,
  timingSafeEqual,
  verifySharedSecret,
  verifyWebhook,
} from "../../core/signatures.ts";

export type {
  VerifiedWebhook,
  VerifyOptions,
  WebhookInput,
} from "../../core/signatures.ts";

// ---------------------------------------------------------------------------
// Stripe

/** Stripe signs with the endpoint secret's UTF-8 bytes, not its base64 decoding. */
const stripeSignature = hmacHex;

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
 * `whsec_…` secret and parses the event. Pass several secrets while rolling the
 * endpoint secret. Runs on WebCrypto, so it needs no `stripe` package.
 */
export async function verifyStripeWebhook<T = unknown>(
  input: WebhookInput,
  secrets: string | readonly string[],
  options: VerifyOptions = {},
): Promise<Result<VerifiedWebhook<T>>> {
  const value = header(input.headers, "stripe-signature");

  if (!value) {
    return err(
      unauthorized(
        "WEBHOOK_MISSING_HEADERS",
        "Missing Stripe-Signature header",
      ),
    );
  }

  const parts = value.split(",").map((part) => {
    const index = part.indexOf("=");

    return [part.slice(0, index).trim(), part.slice(index + 1).trim()] as const;
  });

  const timestamp = parts.find(([name]) => name === "t")?.[1] ?? "";
  const offered = parts.filter(([name]) => name === "v1").map(([, sig]) => sig);

  if (!/^\d+$/.test(timestamp)) {
    return err(
      unauthorized("WEBHOOK_INVALID_TIMESTAMP", "Invalid webhook timestamp"),
    );
  }

  const namespace = optionalTemporal();

  if (namespace === undefined) {
    return err(temporalMissing());
  }

  const seconds = Number(timestamp);

  const now =
    (options.now?.() ?? namespace.Now.instant()).epochMilliseconds / 1000;

  if (Math.abs(now - seconds) > (options.tolerance ?? 300)) {
    return err(
      unauthorized(
        "WEBHOOK_TIMESTAMP_OUT_OF_RANGE",
        "Webhook timestamp is outside the tolerance",
      ),
    );
  }

  const body = input instanceof Request ? await input.text() : input.body;
  let valid = false;

  for (const secret of typeof secrets === "string" ? [secrets] : secrets) {
    const expected = await stripeSignature(secret, `${timestamp}.${body}`);

    for (const candidate of offered) {
      if (timingSafeEqual(candidate, expected)) {
        valid = true;
      }
    }
  }

  if (!valid) {
    return err(
      unauthorized("WEBHOOK_INVALID_SIGNATURE", "Invalid webhook signature"),
    );
  }

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

  const replay = await replayed(
    options,
    id,
    namespace.Instant.fromEpochMilliseconds(
      (seconds + (options.tolerance ?? 300)) * 1000,
    ),
  );

  if (replay) {
    return err(replay);
  }

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
 * `createWebhookInbox({ source: 'stripe', verify: stripeInboxVerify(secret)
 * })`: stores Stripe events keyed by their event id.
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
 * export const POST = authHook(
 *   "custom_access_token",
 *   env.AUTH_HOOK_SECRET,
 *   async ({ claims, user_id }) => ({
 *     claims: { ...claims, tenant_id: await organizationFor(user_id) },
 *   }),
 * );
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

    if (!verified.ok) {
      return Response.json(
        hookError(verified.error.status, verified.error.message),
        { status: verified.error.status },
      );
    }

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
  if (typeof value !== "object" || value === null) {
    return false;
  }

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
 * Reads a database webhook payload for `table` as an app-cased change. Returns
 * `null` for other tables or payloads that aren't database webhooks.
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
  ) {
    return null;
  }

  return {
    type: payload.type,
    table,
    record: payload.record ? toApp(meta, payload.record) : null,
    oldRecord: payload.old_record ? toApp(meta, payload.old_record) : null,
  };
}
