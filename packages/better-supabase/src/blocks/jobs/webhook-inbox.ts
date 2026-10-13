import type { BlockTransport } from "../../core/block-transport.ts";
import type { SqlClient } from "../../postgres/executor.ts";
import type { DrainResult, JobHandler } from "./types.ts";

import {
  budget,
  DEFAULT_BLOCK_SCHEMA,
  leaseHeartbeat,
} from "../../core/block-helpers.ts";
import { dbError } from "../../core/errors.ts";
import {
  problemResponse,
  type BlockProblemOptions,
} from "../../core/problem.ts";
import { ok, type AsyncResult, type Result } from "../../core/result.ts";
import { verifyWebhook } from "../../core/signatures.ts";
import {
  applyTemporal,
  errorText,
  readBodyCapped,
  run,
  seconds,
  toInstant,
  workerId,
  type BlockTemporalOptions,
} from "../shared.ts";

export interface WebhookInboxMessage<T = unknown> {
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
export interface WebhookInboxEvent {
  /** The sender's message id; the inbox stores each one once. */
  readonly id: string;
  readonly payload: unknown;
  /** Defaults to `typeOf(payload)`. */
  readonly type?: string | null;
  /** Defaults to `tenantOf(payload)`. */
  readonly tenant?: string | null;
  readonly headers?: Readonly<Record<string, string>>;
}

export interface WebhookInboxOptions
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
  /**
   * The largest body `receive` reads; a larger one gets 413 without being
   * read to the end. Defaults to 1 MiB.
   */
  readonly maxBodyBytes?: number;
}

export interface WebhookInboxProcessOptions {
  /** Messages claimed at once. Defaults to 10. */
  readonly batch?: number;
  /**
   * How long a claimed message stays with this worker. It is renewed when
   * the message's turn in the batch comes and every half lease while the
   * handler runs. Defaults to 300 seconds.
   */
  readonly lease?: number | string;
  /**
   * Stop claiming after this many ms, so a backlog can't outrun a
   * serverless function's maximum duration; claimed messages still finish.
   * Defaults to no limit.
   */
  readonly budgetMs?: number;
}

export interface WebhookInboxListOptions {
  readonly tenant: string;
  /** Only this status: `pending`, `processing`, `processed` or `dead`. */
  readonly status?: "pending" | "processing" | "processed" | "dead";
  /** Defaults to 100, at most 1000. */
  readonly limit?: number;
}

/** A stored message as `list` returns it. */
export interface WebhookInboxEntry {
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

export interface WebhookInboxPurgeOptions {
  /** Defaults to `30 days`; `0` with `tenant` removes all of that tenant's processed messages. */
  readonly olderThan?: number | string;
  readonly includeDead?: boolean;
  readonly tenant?: string;
  readonly batch?: number;
  /** The schema the functions live in, over a transport. Defaults to `better_supabase`. */
  readonly schema?: string;
}

/**
 * Deletes processed messages from the inbox (`purge_webhooks`) over a
 * service SQL connection or a service-role transport; returns how many.
 */
export function purgeWebhookInbox(
  source: SqlClient | BlockTransport,
  options: WebhookInboxPurgeOptions = {},
): AsyncResult<number> {
  const args = {
    older_than: seconds(options.olderThan ?? "30 days"),
    include_dead: options.includeDead ?? false,
    batch: options.batch ?? 10_000,
    for_tenant: options.tenant ?? null,
  };
  return run(async () => {
    if ("call" in source) {
      return Number(
        (await source.call(
          options.schema ?? DEFAULT_BLOCK_SCHEMA,
          "purge_webhooks",
          args,
        )) ?? 0,
      );
    }
    const [row] = await source.queryRaw<{ purged: number }>(
      "select better_supabase.purge_webhooks($1::interval, $2, $3, $4) as purged",
      [args.older_than, args.include_dead, args.batch, args.for_tenant],
    );
    return row?.purged ?? 0;
  });
}

export interface WebhookInbox {
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
  store(
    event: WebhookInboxEvent,
  ): AsyncResult<{ id: number; duplicate: boolean }>;
  /**
   * Processes stored messages until none are ready, or until `budgetMs`
   * is spent. A message whose lease another claim took over is skipped,
   * and its outcome is not counted.
   */
  process<T = unknown>(
    handler: (message: WebhookInboxMessage<T>) => unknown,
    options?: WebhookInboxProcessOptions,
  ): Promise<DrainResult>;
  /** A tenant's messages of this source, newest first. */
  list(options: WebhookInboxListOptions): AsyncResult<WebhookInboxEntry[]>;
  /** Deletes old processed (and, with `includeDead`, dead) messages of this source's table; returns how many. */
  purge(options?: WebhookInboxPurgeOptions): AsyncResult<number>;
  /** A job handler that runs `purge`; schedule it nightly. */
  purgeJob(options?: WebhookInboxPurgeOptions): JobHandler<unknown>;
}

interface WebhookInboxRow {
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
  status?: WebhookInboxEntry["status"];
  last_error?: string | null;
  processed_at?: Date | string | null;
}

function defaultType(payload: unknown): string | null {
  if (typeof payload !== "object" || payload === null) return null;
  // SAFETY: payload is a non-null object here, and type is checked below.
  const type = (payload as { type?: unknown }).type;
  return typeof type === "string" ? type : null;
}

/** The arguments of one `receive_webhook` call. */
export interface ReceiveWebhookInput {
  readonly source: string;
  readonly id: string;
  readonly type: string | null | undefined;
  readonly payload: unknown;
  readonly headers: Readonly<Record<string, string>>;
  readonly tenant: string | null;
  readonly maxAttempts?: number | undefined;
}

/** Stores one webhook through `receive_webhook`; `duplicate` when the id was stored before. */
export async function receiveWebhook(
  sql: SqlClient,
  input: ReceiveWebhookInput,
): Promise<{ id: number; duplicate: boolean }> {
  const [row] = await sql.queryRaw<{
    id: string | number;
    duplicate: boolean;
  }>(
    "select * from better_supabase.receive_webhook($1, $2, $3, $4, $5, $6, $7)",
    [
      input.source,
      input.id,
      input.type ?? null,
      JSON.stringify(input.payload),
      JSON.stringify(input.headers),
      input.tenant,
      input.maxAttempts ?? null,
    ],
  );
  return { id: Number(row!.id), duplicate: row!.duplicate };
}

/** Store-then-process webhooks: acknowledge fast, process with retries, never twice. */
export function createWebhookInbox(
  sql: SqlClient,
  options: WebhookInboxOptions,
): WebhookInbox {
  applyTemporal(options);
  const worker = options.worker ?? workerId();
  const format = options.problem;
  const maxAttempts = options.maxAttempts ?? 8;
  if (!Number.isInteger(maxAttempts) || maxAttempts < 1) {
    throw new TypeError(
      `createWebhookInbox maxAttempts must be a positive integer, not ${String(maxAttempts)}`,
    );
  }
  const maxBodyBytes = options.maxBodyBytes ?? 1_048_576;
  if (!Number.isInteger(maxBodyBytes) || maxBodyBytes < 1) {
    throw new TypeError(
      `createWebhookInbox maxBodyBytes must be a positive integer, not ${String(maxBodyBytes)}`,
    );
  }

  const verified = async (
    request: Request,
    body: string,
  ): Promise<
    Result<{ id: string; payload: unknown; tenant?: string | null }>
  > => {
    if (options.verify) return options.verify(request, body);
    const result = await verifyWebhook(
      { headers: request.headers, body },
      options.secrets ?? [],
    );
    return result.ok
      ? ok({ id: result.data.id, payload: result.data.payload })
      : result;
  };

  const save = (event: WebhookInboxEvent) =>
    run(() =>
      receiveWebhook(sql, {
        source: options.source,
        id: event.id,
        type:
          event.type === undefined
            ? (options.typeOf ?? defaultType)(event.payload)
            : event.type,
        payload: event.payload,
        headers: event.headers ?? {},
        tenant:
          (event.tenant === undefined
            ? options.tenantOf?.(event.payload)
            : event.tenant) ?? null,
        maxAttempts,
      }),
    );

  return {
    store: save,
    list: (listOptions) =>
      run(async () => {
        const rows = await sql.queryRaw<WebhookInboxRow>(
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
    purge: (purgeOptions) => purgeWebhookInbox(sql, purgeOptions),
    purgeJob: (purgeOptions) => async () =>
      purgeWebhookInbox(sql, purgeOptions).orThrow(),
    async receive(request) {
      const instance = new URL(request.url).pathname;
      if (request.method !== "POST") {
        return new Response(null, { status: 405, headers: { allow: "POST" } });
      }
      if (!options.verify && !options.secrets) {
        throw new TypeError(
          `The inbox for "${options.source}" has no \`secrets\` or \`verify\`, so it only stores events through \`store\``,
        );
      }
      const body = await readBodyCapped(request.clone(), maxBodyBytes);
      if (body === undefined) {
        return problemResponse(
          {
            ...dbError("invalid_input", "The body is too large", {
              code: "WEBHOOK_TOO_LARGE",
            }),
            status: 413,
          },
          { instance, format },
        );
      }
      const message = await verified(request, body);
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
      const lease = seconds(processOptions.lease ?? 300);
      const spent = budget(processOptions.budgetMs);
      for (;;) {
        if (spent.expired()) return { succeeded, failed };
        const rows = await sql.queryRaw<WebhookInboxRow>(
          "select * from better_supabase.claim_webhooks($1, $2, $3, $4::interval)",
          [options.source, worker, processOptions.batch ?? 10, lease],
        );
        if (rows.length === 0) return { succeeded, failed };
        for (const row of rows) {
          const id = Number(row.id);
          const attempt = row.attempts;
          // Renews the lease, which ran from the claim while earlier messages
          // of the batch were handled. No lease: another claim took it over.
          const extend = async (): Promise<number | undefined> => {
            const [held] = await sql.queryRaw<{ lease: number | null }>(
              "select better_supabase.extend_webhook($1, $2, $3, $4::interval) as lease",
              [id, worker, attempt, lease],
            );
            return held?.lease ?? undefined;
          };
          const leaseSeconds = await extend();
          if (leaseSeconds === undefined) continue;
          const message: WebhookInboxMessage<never> = {
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
                "select better_supabase.checkpoint_webhook($1, $2, $3, $4) as saved",
                [id, worker, JSON.stringify(fields), attempt],
              );
              return saved?.saved ?? false;
            },
          };
          const stopHeartbeat = leaseHeartbeat(
            leaseSeconds,
            () => void extend().catch(() => undefined),
          );
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
            const [done] = await sql.queryRaw<{ done: boolean }>(
              "select better_supabase.complete_webhook($1, $2, $3) as done",
              [message.id, worker, attempt],
            );
            if (done?.done !== false) succeeded += 1;
          } catch (cause) {
            await sql.queryRaw(
              "select better_supabase.fail_webhook($1, $2, $3, null, $4)",
              [message.id, worker, errorText(cause), attempt],
            );
            failed += 1;
          } finally {
            stopHeartbeat();
          }
        }
      }
    },
  };
}
