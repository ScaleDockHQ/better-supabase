import type { SqlClient } from "../../postgres/executor.ts";
import type { DrainResult } from "./queue.ts";

import { dbError } from "../../core/errors.ts";
import { problemResponse } from "../../core/problem.ts";
import { type AsyncResult, ok, type Result } from "../../core/result.ts";
import { verifyWebhook } from "../webhooks/verify.ts";
import { errorText, run, seconds, toInstant, workerId } from "./shared.ts";

// ---------------------------------------------------------------------------
// Idempotency keys (SQL module `idempotency`)

export interface IdempotencyOptions {
  /**
   * Separates keys of different callers, endpoints or tenants. Defaults to a
   * hash of the caller's credentials (the `Authorization` header or the
   * Supabase auth cookies), so one caller never replays another's response.
   * Pass the verified user id to keep keys across token refreshes.
   */
  readonly scope?: string | ((request: Request) => string);
  /** How long a completed response is replayed. Defaults to `24 hours`. */
  readonly ttl?: number | string;
  /** How long a running request holds the key. Defaults to `1 minute`. */
  readonly lock?: number | string;
  /** Answer 400 when the header is missing. Defaults to false (run without a key). */
  readonly required?: boolean;
  /** Defaults to `Idempotency-Key`. */
  readonly header?: string;
}

export type IdempotencyState = "started" | "replay" | "running" | "mismatch";

export interface Idempotency {
  /**
   * Runs `handler` at most once per key: retries with the same key and body
   * get the stored response (with `Idempotency-Replayed: true`).
   */
  handle(
    request: Request,
    handler: (request: Request) => Promise<Response> | Response,
  ): Promise<Response>;
  /** The lower-level protocol, for non-HTTP callers. */
  begin(
    key: string,
    fingerprint: string,
    scope?: string,
  ): AsyncResult<{
    state: IdempotencyState;
    status: number | null;
    body: unknown;
  }>;
  complete(
    key: string,
    status: number,
    body: unknown,
    scope?: string,
  ): AsyncResult<void>;
  release(key: string, scope?: string): AsyncResult<void>;
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

const AUTH_COOKIE = /^sb-.+-auth-token(?:\.\d+)?$/;

/** A hash of the credentials the request carries, or `''` without any. */
async function callerScope(request: Request): Promise<string> {
  const authorization = request.headers.get("authorization");
  const cookies = (request.headers.get("cookie") ?? "")
    .split(";")
    .map((pair) => pair.trim())
    .filter((pair) => AUTH_COOKIE.test(pair.split("=", 1)[0] ?? ""))
    .sort();
  const credential = authorization ?? cookies.join(";");
  return credential === "" ? "" : `caller:${await sha256(credential)}`;
}

interface StoredResponse {
  readonly body: string;
  readonly contentType: string | null;
}

/** HTTP idempotency keys (IETF `Idempotency-Key` header) over the `idempotency` SQL module. */
export function createIdempotency(
  sql: SqlClient,
  options: IdempotencyOptions = {},
): Idempotency {
  const headerName = options.header ?? "idempotency-key";
  const ttl = seconds(options.ttl ?? "24 hours");
  const lock = seconds(options.lock ?? "1 minute");

  const begin: Idempotency["begin"] = (key, fingerprint, scope = "") =>
    run(async () => {
      const [row] = await sql.queryRaw<{
        state: IdempotencyState;
        status_code: number | null;
        response: unknown;
      }>(
        "select * from better_supabase.begin_idempotent($1, $2, $3, $4::interval, $5::interval)",
        [scope, key, fingerprint, ttl, lock],
      );
      return {
        state: row!.state,
        status: row!.status_code,
        body: row!.response,
      };
    });
  const complete: Idempotency["complete"] = (key, status, body, scope = "") =>
    run(async () => {
      await sql.queryRaw(
        "select better_supabase.complete_idempotent($1, $2, $3, $4)",
        [scope, key, status, JSON.stringify(body)],
      );
    });
  const release: Idempotency["release"] = (key, scope = "") =>
    run(async () => {
      await sql.queryRaw("select better_supabase.release_idempotent($1, $2)", [
        scope,
        key,
      ]);
    });

  return {
    begin,
    complete,
    release,
    async handle(request, handler) {
      const key = request.headers.get(headerName);
      const instance = new URL(request.url).pathname;
      if (!key) {
        return options.required
          ? problemResponse(
              dbError(
                "invalid_request",
                `The ${headerName} header is required`,
                {
                  code: "IDEMPOTENCY_KEY_MISSING",
                },
              ),
              { instance },
            )
          : handler(request);
      }
      if (key.length > 255) {
        return problemResponse(
          dbError("invalid_request", `The ${headerName} header is too long`, {
            code: "IDEMPOTENCY_KEY_INVALID",
          }),
          { instance },
        );
      }
      const scope =
        typeof options.scope === "function"
          ? options.scope(request)
          : (options.scope ?? (await callerScope(request)));
      const body = await request.clone().text();
      const fingerprint = await sha256(
        `${request.method} ${instance}\n${body}`,
      );
      const started = await begin(key, fingerprint, scope);
      if (!started.ok) return problemResponse(started.error, { instance });
      const { state } = started.data;
      switch (state) {
        case "replay": {
          // SAFETY: the replay state is only written with the stored response
          // of the first request.
          const stored = started.data.body as StoredResponse;
          return new Response(stored.body, {
            status: started.data.status ?? 200,
            headers: {
              ...(stored.contentType
                ? { "content-type": stored.contentType }
                : {}),
              "idempotency-replayed": "true",
            },
          });
        }
        case "running":
          return problemResponse(
            dbError(
              "conflict",
              "A request with this idempotency key is still running",
              {
                code: "IDEMPOTENCY_KEY_IN_USE",
              },
            ),
            { instance, headers: { "retry-after": "1" } },
          );
        case "mismatch":
          return problemResponse(
            dbError(
              "validation",
              "This idempotency key was used for a different request",
              {
                code: "IDEMPOTENCY_KEY_REUSED",
                issues: [
                  {
                    message: "Use a new key for a new request",
                    path: [headerName],
                  },
                ],
              },
            ),
            { instance },
          );
        case "started":
          break;
        default: {
          const unknown: never = state;
          throw new TypeError(`Unknown idempotency state ${String(unknown)}`);
        }
      }
      let response: Response;
      try {
        response = await handler(request);
      } catch (cause) {
        await release(key, scope);
        throw cause;
      }
      if (response.status >= 500) {
        await release(key, scope);
        return response;
      }
      const stored: StoredResponse = {
        body: await response.clone().text(),
        contentType: response.headers.get("content-type"),
      };
      await complete(key, response.status, stored, scope);
      return response;
    },
  };
}

// ---------------------------------------------------------------------------
// Webhook inbox (SQL module `webhook-inbox`)

export interface InboxMessage<T = unknown> {
  readonly id: number;
  readonly source: string;
  readonly messageId: string;
  readonly type: string | null;
  readonly payload: T;
  readonly headers: Readonly<Record<string, string>>;
  readonly attempts: number;
  readonly receivedAt: Temporal.Instant;
  /** The tenant the message was stored for, or null. */
  readonly tenant: string | null;
  /** Progress an earlier attempt saved with `checkpoint`, `{}` at first. */
  readonly progress: Readonly<Record<string, unknown>>;
  /**
   * Saves progress mid-processing (merged into `progress`), so a retry
   * resumes there, such as a provider's page cursor. `false` when the lease
   * was lost. Only while the handler runs.
   */
  checkpoint(fields: Readonly<Record<string, unknown>>): Promise<boolean>;
}

/** A verified event to store, from `verify` or from `store` for a provider SDK that verifies itself. */
export interface InboxEvent {
  /** The sender's message id; the inbox stores each one once. */
  readonly id: string;
  readonly payload: unknown;
  /** Defaults to `typeOf(payload)`. */
  readonly type?: string | null;
  /** Defaults to `tenantOf(payload)`. */
  readonly tenant?: string | null;
  readonly headers?: Readonly<Record<string, string>>;
}

export interface InboxOptions {
  /** Name of the sender, e.g. `stripe` or `supabase-auth`. */
  readonly source: string;
  /** Standard Webhooks secrets; the signature is verified before storing. */
  readonly secrets?: string | readonly string[];
  /**
   * Custom verification for senders that don't use Standard Webhooks. It
   * may also return the event's tenant.
   */
  readonly verify?: (
    request: Request,
    body: string,
  ) => Promise<
    Result<{ id: string; payload: unknown; tenant?: string | null }>
  >;
  /** Event type from the payload. Defaults to `payload.type`. */
  readonly typeOf?: (payload: unknown) => string | null;
  /** The tenant a payload belongs to, for per-tenant integrations. Defaults to none. */
  readonly tenantOf?: (payload: unknown) => string | null | undefined;
  /** Headers kept with the message. Defaults to none. */
  readonly keepHeaders?: readonly string[];
  readonly worker?: string;
}

export interface InboxListOptions {
  readonly tenant: string;
  /** Only this status: `pending`, `processing`, `processed` or `dead`. */
  readonly status?: "pending" | "processing" | "processed" | "dead";
  /** Defaults to 100, at most 1000. */
  readonly limit?: number;
}

/** A stored message as `list` returns it. */
export interface InboxEntry {
  readonly id: number;
  readonly messageId: string;
  readonly type: string | null;
  readonly status: "pending" | "processing" | "processed" | "dead";
  readonly attempts: number;
  readonly lastError: string | null;
  readonly tenant: string | null;
  readonly receivedAt: Temporal.Instant;
  readonly processedAt: Temporal.Instant | null;
}

export interface InboxPurgeOptions {
  /** Defaults to `30 days`; `0` with `tenant` removes all of that tenant's processed messages. */
  readonly olderThan?: number | string;
  readonly includeDead?: boolean;
  readonly tenant?: string;
  readonly batch?: number;
}

export interface Inbox {
  /** Verifies and stores a webhook; answers 202, or 200 for a duplicate delivery. */
  receive(request: Request): Promise<Response>;
  /**
   * Stores an event your code already verified (a provider SDK that
   * verifies and parses in one call). `duplicate` when the id was stored
   * before.
   */
  store(event: InboxEvent): AsyncResult<{ id: number; duplicate: boolean }>;
  /** Processes stored messages until none are ready. */
  process<T = unknown>(
    handler: (message: InboxMessage<T>) => unknown,
    options?: { readonly batch?: number; readonly lease?: number | string },
  ): Promise<DrainResult>;
  /** A tenant's messages of this source, newest first. */
  list(options: InboxListOptions): AsyncResult<InboxEntry[]>;
  /** Deletes old processed (and, with `includeDead`, dead) messages of this source's table; returns how many. */
  purge(options?: InboxPurgeOptions): AsyncResult<number>;
}

interface InboxRow {
  id: string | number;
  source: string;
  message_id: string;
  event_type: string | null;
  payload: unknown;
  headers: Record<string, string>;
  attempts: number;
  received_at: Date | string;
  tenant?: string | null;
  checkpoint?: Record<string, unknown> | null;
  status?: InboxEntry["status"];
  last_error?: string | null;
  processed_at?: Date | string | null;
}

function defaultType(payload: unknown): string | null {
  if (typeof payload !== "object" || payload === null) return null;
  // SAFETY: payload is a non-null object here, and type is checked below.
  const type = (payload as { type?: unknown }).type;
  return typeof type === "string" ? type : null;
}

/** Store-then-process webhooks: acknowledge fast, process with retries, never twice. */
export function createInbox(sql: SqlClient, options: InboxOptions): Inbox {
  const worker = options.worker ?? workerId();
  if (!options.secrets && !options.verify) {
    throw new TypeError(
      "createInbox needs `secrets` (Standard Webhooks) or `verify`",
    );
  }

  const verified = async (
    request: Request,
  ): Promise<
    Result<{ id: string; payload: unknown; tenant?: string | null }>
  > => {
    if (options.verify)
      return options.verify(request, await request.clone().text());
    const result = await verifyWebhook(request, options.secrets!);
    return result.ok
      ? ok({ id: result.data.id, payload: result.data.payload })
      : result;
  };

  const save = (event: InboxEvent) =>
    run(async () => {
      const [row] = await sql.queryRaw<{
        id: string | number;
        duplicate: boolean;
      }>(
        "select * from better_supabase.receive_webhook($1, $2, $3, $4, $5, $6)",
        [
          options.source,
          event.id,
          event.type === undefined
            ? (options.typeOf ?? defaultType)(event.payload)
            : event.type,
          JSON.stringify(event.payload),
          JSON.stringify(event.headers ?? {}),
          (event.tenant === undefined
            ? options.tenantOf?.(event.payload)
            : event.tenant) ?? null,
        ],
      );
      return { id: Number(row!.id), duplicate: row!.duplicate };
    });

  return {
    store: save,
    list: (listOptions) =>
      run(async () => {
        const rows = await sql.queryRaw<InboxRow>(
          "select * from better_supabase.list_webhooks($1, $2, $3, $4)",
          [
            listOptions.tenant,
            options.source,
            listOptions.status ?? null,
            listOptions.limit ?? 100,
          ],
        );
        return rows.map((row) => ({
          id: Number(row.id),
          messageId: row.message_id,
          type: row.event_type,
          status: row.status ?? "pending",
          attempts: row.attempts,
          lastError: row.last_error ?? null,
          tenant: row.tenant ?? null,
          receivedAt: toInstant(row.received_at),
          processedAt:
            row.processed_at === null || row.processed_at === undefined
              ? null
              : toInstant(row.processed_at),
        }));
      }),
    purge: (purgeOptions = {}) =>
      run(async () => {
        const [row] = await sql.queryRaw<{ purged: number }>(
          "select better_supabase.purge_webhooks($1::interval, $2, $3, $4) as purged",
          [
            seconds(purgeOptions.olderThan ?? "30 days"),
            purgeOptions.includeDead ?? false,
            purgeOptions.batch ?? 10_000,
            purgeOptions.tenant ?? null,
          ],
        );
        return row?.purged ?? 0;
      }),
    async receive(request) {
      const instance = new URL(request.url).pathname;
      if (request.method !== "POST") {
        return new Response(null, { status: 405, headers: { allow: "POST" } });
      }
      const message = await verified(request);
      if (!message.ok) return problemResponse(message.error, { instance });
      const headers = Object.fromEntries(
        (options.keepHeaders ?? []).flatMap((name) => {
          const value = request.headers.get(name);
          return value === null ? [] : [[name.toLowerCase(), value]];
        }),
      );
      const stored = await save({
        id: message.data.id,
        payload: message.data.payload,
        headers,
        ...(message.data.tenant === undefined
          ? {}
          : { tenant: message.data.tenant }),
      });
      if (!stored.ok) return problemResponse(stored.error, { instance });
      return Response.json(stored.data, {
        status: stored.data.duplicate ? 200 : 202,
      });
    },

    async process(handler, processOptions = {}) {
      let succeeded = 0;
      let failed = 0;
      for (;;) {
        const rows = await sql.queryRaw<InboxRow>(
          "select * from better_supabase.claim_webhooks($1, $2, $3, $4::interval)",
          [
            options.source,
            worker,
            processOptions.batch ?? 10,
            seconds(processOptions.lease ?? 300),
          ],
        );
        if (rows.length === 0) return { succeeded, failed };
        for (const row of rows) {
          const id = Number(row.id);
          const message: InboxMessage<never> = {
            id,
            source: row.source,
            messageId: row.message_id,
            type: row.event_type,
            // SAFETY: the handler's payload type comes from its event type,
            // and the inbox stores the payload as JSON.
            payload: row.payload as never,
            headers: row.headers,
            attempts: row.attempts,
            receivedAt: toInstant(row.received_at),
            tenant: row.tenant ?? null,
            progress: row.checkpoint ?? {},
            async checkpoint(fields) {
              const [saved] = await sql.queryRaw<{ saved: boolean }>(
                "select better_supabase.checkpoint_webhook($1, $2, $3) as saved",
                [id, worker, JSON.stringify(fields)],
              );
              return saved?.saved ?? false;
            },
          };
          try {
            const outcome: unknown = await handler(message);
            if (
              typeof outcome === "object" &&
              outcome !== null &&
              "ok" in outcome &&
              outcome.ok === false
            ) {
              // SAFETY: the check above proves outcome is a failed Result,
              // which has an error field.
              throw new Error(
                errorText(
                  (outcome as { error?: unknown }).error ??
                    "The handler failed",
                ),
              );
            }
            await sql.queryRaw(
              "select better_supabase.complete_webhook($1, $2)",
              [message.id, worker],
            );
            succeeded += 1;
          } catch (cause) {
            await sql.queryRaw(
              "select better_supabase.fail_webhook($1, $2, $3)",
              [message.id, worker, errorText(cause)],
            );
            failed += 1;
          }
        }
      }
    },
  };
}

// ---------------------------------------------------------------------------
// Audit retention (SQL module `audit`)

export interface PurgeAuditLogOptions {
  /** How long entries are kept when `retention` has no answer. Defaults to `1 year`. */
  readonly olderThan?: number | string;
  /** The most entries deleted per tenant in one call. Defaults to 10000. */
  readonly batch?: number;
  /**
   * Days a tenant keeps its entries (a plan's retention, say); `undefined`
   * uses `olderThan`. Called with `null` for entries without a tenant.
   * Retention shorter than a day is not supported.
   */
  readonly retention?: (
    tenant: string | null,
  ) => number | undefined | Promise<number | undefined>;
}

/**
 * Deletes audit entries past their retention and returns how many. Without
 * `retention` it is one `purge_audit_log` call (which honours an
 * `audit_retention` SQL hook); with it, each tenant is purged with its own
 * interval. Run it from a schedule until it returns 0.
 */
export function purgeAuditLog(
  sql: SqlClient,
  options: PurgeAuditLogOptions = {},
): AsyncResult<number> {
  const olderThan = seconds(options.olderThan ?? "1 year");
  const batch = options.batch ?? 10_000;
  const purge = async (params: unknown[], call: string) => {
    const [row] = await sql.queryRaw<{ n: number | string }>(
      `select better_supabase.purge_audit_log(${call}) as n`,
      params,
    );
    return Number(row?.n ?? 0);
  };
  const { retention } = options;
  if (!retention) {
    return run(() => purge([olderThan, batch], "$1::interval, $2"));
  }
  return run(async () => {
    const tenants = await sql.queryRaw<{ tenant: string | null }>(
      "select tenant::text from better_supabase.audit_events_tenants($1::interval) as tenant",
      ["1 day"],
    );
    let purged = 0;
    for (const { tenant } of tenants) {
      const days = await retention(tenant);
      const keep = days === undefined ? olderThan : `${days} days`;
      purged += await purge(
        [keep, batch, tenant],
        "$1::interval, $2, $3, true",
      );
    }
    return purged;
  });
}
