import type { SqlClient } from "../../postgres/executor.ts";
import type { DrainResult } from "./queue.ts";

import { dbError } from "../../core/errors.ts";
import {
  type BlockProblemOptions,
  problemResponse,
} from "../../core/problem.ts";
import { type AsyncResult, ok, type Result } from "../../core/result.ts";
import {
  errorText,
  run,
  seconds,
  toInstant,
  workerId,
  type BlockTemporalOptions,
  applyTemporal,
} from "../shared.ts";
import { verifyWebhook } from "../webhooks/verify.ts";

// ---------------------------------------------------------------------------
// Idempotency keys (SQL module `idempotency`)

export interface IdempotencyOptions
  extends BlockProblemOptions, BlockTemporalOptions {
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
    /** The token `complete` and `release` need, when `state` is `started`. */
    holder: string | undefined;
  }>;
  /**
   * Stores the response for `holder`. `false` when the lock ran out and
   * another caller took the key over, so the response was not stored.
   */
  complete(
    key: string,
    holder: string,
    status: number,
    body: unknown,
    scope?: string,
  ): AsyncResult<boolean>;
  /** Forgets the key so it can be retried; `false` when `holder` lost it. */
  release(key: string, holder: string, scope?: string): AsyncResult<boolean>;
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
  applyTemporal(options);
  const headerName = options.header ?? "idempotency-key";
  const format = options.problem;
  const ttl = seconds(options.ttl ?? "24 hours");
  const lock = seconds(options.lock ?? "1 minute");

  const begin: Idempotency["begin"] = (key, fingerprint, scope = "") =>
    run(async () => {
      const [row] = await sql.queryRaw<{
        state: IdempotencyState;
        status_code: number | null;
        response: unknown;
        holder: string | null;
      }>(
        "select * from better_supabase.begin_idempotent($1, $2, $3, $4::interval, $5::interval)",
        [scope, key, fingerprint, ttl, lock],
      );
      return {
        state: row!.state,
        status: row!.status_code,
        body: row!.response,
        holder: row!.holder ?? undefined,
      };
    });
  const complete: Idempotency["complete"] = (
    key,
    holder,
    status,
    body,
    scope = "",
  ) =>
    run(async () => {
      const [row] = await sql.queryRaw<{ done: boolean }>(
        "select better_supabase.complete_idempotent($1, $2, $3, $4, $5) as done",
        [scope, key, holder, status, JSON.stringify(body)],
      );
      return row?.done === true;
    });
  const release: Idempotency["release"] = (key, holder, scope = "") =>
    run(async () => {
      const [row] = await sql.queryRaw<{ done: boolean }>(
        "select better_supabase.release_idempotent($1, $2, $3) as done",
        [scope, key, holder],
      );
      return row?.done === true;
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
              { instance, format },
            )
          : handler(request);
      }
      if (key.length > 255) {
        return problemResponse(
          dbError("invalid_request", `The ${headerName} header is too long`, {
            code: "IDEMPOTENCY_KEY_INVALID",
          }),
          { instance, format },
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
      if (!started.ok)
        return problemResponse(started.error, { instance, format });
      const { state, holder = "" } = started.data;
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
            { instance, format, headers: { "retry-after": "1" } },
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
            { instance, format },
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
        await release(key, holder, scope);
        throw cause;
      }
      if (response.status >= 500) {
        await release(key, holder, scope);
        return response;
      }
      const stored: StoredResponse = {
        body: await response.clone().text(),
        contentType: response.headers.get("content-type"),
      };
      await complete(key, holder, response.status, stored, scope);
      return response;
    },
  };
}

// ---------------------------------------------------------------------------
// Leases (SQL module `idempotency`)

export interface LeaseOptions {
  /** How long the lease holds without an `extend`. Defaults to 60 seconds. */
  readonly seconds?: number;
  readonly scope?: string;
}

/** The held lease, passed to the `withLease` callback. */
export interface Lease {
  readonly holder: string;
  /** Moves the expiry; `false` once the lease was lost to another holder. */
  extend(seconds?: number): AsyncResult<boolean>;
}

export type LeaseOutcome<T> =
  | { readonly acquired: true; readonly value: T }
  | { readonly acquired: false };

/**
 * Runs `fn` while holding the lease on `key`, one holder at a time, and
 * releases it afterwards, also when `fn` throws. `{ acquired: false }` while
 * another holder has it. A lease that expires mid-run is taken by the next
 * caller; call `lease.extend()` for long work.
 */
export function withLease<T>(
  sql: SqlClient,
  key: string,
  fn: (lease: Lease) => Promise<T> | T,
  options: LeaseOptions = {},
): AsyncResult<LeaseOutcome<T>> {
  const scope = options.scope ?? "";
  const ttl = options.seconds ?? 60;
  return run(async (): Promise<LeaseOutcome<T>> => {
    const [row] = await sql.queryRaw<{ holder: string | null }>(
      "select better_supabase.acquire_lease($1, $2, $3) as holder",
      [key, ttl, scope],
    );
    const holder = row?.holder;
    if (!holder) return { acquired: false };
    const lease: Lease = {
      holder,
      extend: (next = ttl) =>
        run(async () => {
          const [extended] = await sql.queryRaw<{ done: boolean }>(
            "select better_supabase.extend_lease($1, $2, $3, $4) as done",
            [key, holder, next, scope],
          );
          return extended?.done === true;
        }),
    };
    try {
      return { acquired: true, value: await fn(lease) };
    } finally {
      await sql.queryRaw("select better_supabase.release_lease($1, $2, $3)", [
        key,
        holder,
        scope,
      ]);
    }
  });
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
  /** 1 on the first attempt. */
  readonly attempts: number;
  /**
   * The source's limit when the message was stored. A handler running with
   * `attempts === maxAttempts` is on its last attempt: when it fails, the
   * message is marked dead.
   */
  readonly maxAttempts: number;
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

export interface InboxOptions
  extends BlockProblemOptions, BlockTemporalOptions {
  /** Name of the sender, e.g. `stripe` or `supabase-auth`. */
  readonly source: string;
  /**
   * Standard Webhooks secrets; the signature is verified before storing.
   * Leave out `secrets` and `verify` for a source that only `store` fills
   * (a chat or provider SDK that verifies its own requests); `receive` then
   * throws.
   */
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
  /**
   * Attempts before a message of this source is marked dead, stored with
   * each message as it arrives. Defaults to 8.
   */
  readonly maxAttempts?: number;
}

export interface InboxProcessOptions {
  /** Messages claimed at once. Defaults to 10. */
  readonly batch?: number;
  /** How long a claimed message stays with this worker. Defaults to 300 seconds. */
  readonly lease?: number | string;
  /**
   * Stop claiming after this many ms, so a backlog can't outrun a
   * serverless function's maximum duration; claimed messages still finish.
   * Defaults to no limit.
   */
  readonly budgetMs?: number;
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
  readonly maxAttempts: number;
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
  /**
   * Verifies and stores a webhook; answers 202, or 200 for a duplicate
   * delivery. Throws a `TypeError` when the inbox has neither `secrets` nor
   * `verify`.
   */
  receive(request: Request): Promise<Response>;
  /**
   * Stores an event your code already verified (a provider SDK that
   * verifies and parses in one call). `duplicate` when the id was stored
   * before.
   */
  store(event: InboxEvent): AsyncResult<{ id: number; duplicate: boolean }>;
  /**
   * Processes stored messages until none are ready, or until `budgetMs`
   * is spent.
   */
  process<T = unknown>(
    handler: (message: InboxMessage<T>) => unknown,
    options?: InboxProcessOptions,
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
  max_attempts?: number;
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
  applyTemporal(options);
  const worker = options.worker ?? workerId();
  const format = options.problem;
  const maxAttempts = options.maxAttempts ?? 8;
  if (!Number.isInteger(maxAttempts) || maxAttempts < 1) {
    throw new TypeError(
      `createInbox maxAttempts must be a positive integer, not ${String(maxAttempts)}`,
    );
  }

  const verified = async (
    request: Request,
  ): Promise<
    Result<{ id: string; payload: unknown; tenant?: string | null }>
  > => {
    if (options.verify)
      return options.verify(request, await request.clone().text());
    if (!options.secrets) {
      throw new TypeError(
        `The inbox for "${options.source}" has no \`secrets\` or \`verify\`, so it only stores events through \`store\``,
      );
    }
    const result = await verifyWebhook(request, options.secrets);
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
        "select * from better_supabase.receive_webhook($1, $2, $3, $4, $5, $6, $7)",
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
          maxAttempts,
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
          maxAttempts: row.max_attempts ?? maxAttempts,
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
      if (!message.ok)
        return problemResponse(message.error, { instance, format });
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
      if (!stored.ok)
        return problemResponse(stored.error, { instance, format });
      return Response.json(stored.data, {
        status: stored.data.duplicate ? 200 : 202,
      });
    },

    async process(handler, processOptions = {}) {
      let succeeded = 0;
      let failed = 0;
      const deadline =
        processOptions.budgetMs === undefined
          ? undefined
          : Date.now() + processOptions.budgetMs;
      for (;;) {
        if (deadline !== undefined && Date.now() >= deadline)
          return { succeeded, failed };
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
            maxAttempts: row.max_attempts ?? maxAttempts,
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
