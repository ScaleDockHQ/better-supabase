import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { SqlClient } from "../../postgres/executor.ts";
import type { DrainResult, JobHandler } from "./types.ts";

import {
  type BlockFields,
  blockFields,
  type ExtraFields,
  type FieldsOf,
} from "../../core/block-fields.ts";
import { budget, leaseHeartbeat } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import {
  problemResponse,
  type BlockProblemOptions,
} from "../../core/problem.ts";
import { ok, type AsyncResult, type Result } from "../../core/result.ts";
import { verifyWebhook } from "../../core/signatures.ts";
import {
  applyTemporal,
  blockCall,
  type BlockOptions,
  errorText,
  isRecord,
  readBodyCapped,
  recordOf,
  recordsOf,
  run,
  seconds,
  toInstant,
  workerId,
} from "../shared.ts";

export interface WebhookInboxMessage<
  T = unknown,
  F extends object = Record<never, never>,
> {
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
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
  /**
   * Saves progress mid-processing (merged into `progress`), so a retry
   * resumes there, such as a provider's page cursor. `false` when the lease
   * was lost. Only while the handler runs.
   */
  checkpoint(fields: Readonly<Record<string, unknown>>): Promise<boolean>;
}

/** A verified event to store, from `verify` or from `store` for a provider SDK that verifies itself. */
export interface WebhookInboxEvent<F extends object = Record<never, never>> {
  /** The sender's message id; the inbox stores each one once. */
  readonly id: string;
  readonly payload: unknown;
  /** Defaults to `typeOf(payload)`. */
  readonly type?: string | null;
  /** Defaults to `tenantOf(payload)`. */
  readonly tenant?: string | null;
  readonly headers?: Readonly<Record<string, string>>;
  /** The extra columns of a new message; a duplicate keeps the stored ones. */
  readonly fields?: Partial<F>;
}

export interface WebhookInboxOptions<
  S extends StandardSchemaV1 | undefined = undefined,
>
  extends BlockOptions, BlockProblemOptions {
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
  /**
   * A Standard Schema for the message's extra columns
   * (`blocks.webhook-inbox.options.extraColumns`), keyed by database name.
   * It validates them on `store`, and types and parses them on `list` and
   * on the messages `process` hands the handler.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around `store`, `list` and `purge`. */
  readonly hooks?: NoInfer<BlockHooks<WebhookInbox<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
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
export interface WebhookInboxEntry<F extends object = Record<never, never>> {
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
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
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
  if ("call" in source) {
    return blockCall(source, options.schema)("purge_webhooks", args, (value) =>
      Number(value ?? 0),
    );
  }
  return run(async () => {
    const [row] = await source.queryRaw<{ purged: number }>(
      "select better_supabase.purge_webhooks($1::interval, $2, $3, $4) as purged",
      [args.older_than, args.include_dead, args.batch, args.for_tenant],
    );
    return row?.purged ?? 0;
  });
}

export interface WebhookInbox<F extends object = Record<never, never>> {
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
    event: WebhookInboxEvent<F>,
  ): AsyncResult<{ id: number; duplicate: boolean }>;
  /**
   * Processes stored messages until none are ready, or until `budgetMs`
   * is spent. A message whose lease another claim took over is skipped,
   * and its outcome is not counted. A message whose extra columns the
   * `fields` schema rejects fails without reaching the handler.
   */
  process<T = unknown>(
    handler: (message: WebhookInboxMessage<T, F>) => unknown,
    options?: WebhookInboxProcessOptions,
  ): Promise<DrainResult>;
  /** A tenant's messages of this source, newest first. */
  list(options: WebhookInboxListOptions): AsyncResult<WebhookInboxEntry<F>[]>;
  /** Deletes old processed (and, with `includeDead`, dead) messages of this source's table; returns how many. */
  purge(options?: WebhookInboxPurgeOptions): AsyncResult<number>;
  /** A job handler that runs `purge`; schedule it nightly. */
  purgeJob(options?: WebhookInboxPurgeOptions): JobHandler<unknown>;
}

const STATUSES: ReadonlySet<string> = new Set([
  "pending",
  "processing",
  "processed",
  "dead",
]);

function statusOf(value: unknown): WebhookInboxEntry["status"] {
  if (typeof value !== "string" || !STATUSES.has(value)) return "pending";
  // SAFETY: the set holds exactly the status values.
  return value as WebhookInboxEntry["status"];
}

const nullableText = (value: unknown): string | null =>
  value === null || value === undefined ? null : String(value);

const instantOf = (value: unknown): Temporal.Instant =>
  toInstant(value instanceof Date ? value : String(value));

const headersOf = (value: unknown): Readonly<Record<string, string>> =>
  isRecord(value)
    ? Object.fromEntries(
        Object.entries(value).map(([key, item]) => [key, String(item)]),
      )
    : {};

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

/**
 * Stores one webhook through `receive_webhook` over a service SQL
 * connection; `duplicate` when the id was stored before.
 */
export async function receiveWebhook(
  sql: SqlClient,
  input: ReceiveWebhookInput,
): Promise<{ id: number; duplicate: boolean }> {
  const [row] = await sql.queryRaw<{ value: unknown }>(
    "select better_supabase.receive_webhook($1, $2, $3, $4, $5, $6, $7) as value",
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
  return storedOf(row?.value);
}

function storedOf(value: unknown): { id: number; duplicate: boolean } {
  const row = recordOf(value, "receive_webhook");
  return { id: Number(row["id"]), duplicate: row["duplicate"] === true };
}

/**
 * Store-then-process webhooks: acknowledge fast, process with retries, never
 * twice. Pass a service transport, `sqlTransport(postgres.admin)`: the inbox
 * functions are granted to the service role only.
 */
export function createWebhookInbox<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: WebhookInboxOptions<S>): WebhookInbox<FieldsOf<S>> {
  type F = FieldsOf<S>;
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(
    options.fields,
    "webhook inbox fields",
  );
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

  const save = (event: WebhookInboxEvent<F>) =>
    fields.args(event.fields).andThen((checked) =>
      call(
        "receive_webhook",
        {
          source: options.source,
          message_id: event.id,
          event_type:
            event.type === undefined
              ? (options.typeOf ?? defaultType)(event.payload)
              : event.type,
          payload: event.payload,
          headers: event.headers ?? {},
          tenant:
            (event.tenant === undefined
              ? options.tenantOf?.(event.payload)
              : event.tenant) ?? null,
          max_attempts: maxAttempts,
          fields: checked,
        },
        storedOf,
      ),
    );

  /** Runs a call the worker can't go on without; it throws the `DbError`. */
  const must = <T>(
    fn: string,
    args: Readonly<Record<string, unknown>>,
    then: (value: unknown) => T,
  ): Promise<T> => call(fn, args, then).orThrow();

  const client: WebhookInbox<F> = {
    store: save,
    list: (listOptions) =>
      call(
        "list_webhooks",
        {
          for_tenant: listOptions.tenant,
          for_source: options.source,
          for_status: listOptions.status ?? null,
          max_rows: listOptions.limit ?? 100,
        },
        (value) =>
          recordsOf(value, "list_webhooks").map((row) => ({
            id: Number(row["id"]),
            messageId: String(row["message_id"]),
            type: nullableText(row["event_type"]),
            status: statusOf(row["status"]),
            attempts: Number(row["attempts"]),
            maxAttempts:
              row["max_attempts"] === null || row["max_attempts"] === undefined
                ? maxAttempts
                : Number(row["max_attempts"]),
            lastError: nullableText(row["last_error"]),
            tenant: nullableText(row["tenant"]),
            receivedAt: instantOf(row["received_at"]),
            processedAt:
              row["processed_at"] === null || row["processed_at"] === undefined
                ? null
                : instantOf(row["processed_at"]),
            fields: isRecord(row["fields"]) ? row["fields"] : {},
          })),
      ).andThen(fields.rows),
    purge: (purgeOptions) =>
      purgeWebhookInbox(options.transport, {
        ...(options.schema === undefined ? {} : { schema: options.schema }),
        ...purgeOptions,
      }),
    purgeJob: (purgeOptions) => async () =>
      client.purge(purgeOptions).orThrow(),
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
        const rows = await must(
          "claim_webhooks",
          {
            source: options.source,
            worker,
            batch: processOptions.batch ?? 10,
            lease,
          },
          (value) => recordsOf(value, "claim_webhooks"),
        );
        if (rows.length === 0) return { succeeded, failed };
        for (const row of rows) {
          const id = Number(row["id"]);
          const attempt = Number(row["attempts"]);
          // Renews the lease, which ran from the claim while earlier messages
          // of the batch were handled. No lease: another claim took it over.
          const extend = (): Promise<number | undefined> =>
            must(
              "extend_webhook",
              { inbox_id: id, worker, attempt, lease },
              (value) =>
                value === null || value === undefined
                  ? undefined
                  : Number(value),
            );
          const leaseSeconds = await extend();
          if (leaseSeconds === undefined) continue;
          const stopHeartbeat = leaseHeartbeat(
            leaseSeconds,
            () => void extend().catch(() => undefined),
          );
          try {
            const parsed = await fields.read(
              isRecord(row["fields"]) ? row["fields"] : {},
            );
            if (!parsed.ok) throw new Error(parsed.error.message);
            const message: WebhookInboxMessage<never, F> = {
              id,
              source: String(row["source"]),
              messageId: String(row["message_id"]),
              type: nullableText(row["event_type"]),
              // SAFETY: the handler's payload type comes from its event type,
              // and the inbox stores the payload as JSON.
              payload: row["payload"] as never,
              headers: headersOf(row["headers"]),
              attempts: attempt,
              maxAttempts:
                row["max_attempts"] === null ||
                row["max_attempts"] === undefined
                  ? maxAttempts
                  : Number(row["max_attempts"]),
              receivedAt: instantOf(row["received_at"]),
              tenant: nullableText(row["tenant"]),
              progress: isRecord(row["checkpoint"]) ? row["checkpoint"] : {},
              fields: parsed.data,
              checkpoint: (progress) =>
                must(
                  "checkpoint_webhook",
                  { inbox_id: id, worker, fields: progress, attempt },
                  (value) => value === true,
                ),
            };
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
            const done = await must(
              "complete_webhook",
              { inbox_id: id, worker, attempt },
              (value) => value !== false,
            );
            if (done) succeeded += 1;
          } catch (cause) {
            await must(
              "fail_webhook",
              { inbox_id: id, worker, error: errorText(cause), attempt },
              () => undefined,
            );
            failed += 1;
          } finally {
            stopHeartbeat();
          }
        }
      }
    },
  };
  return withBlockHooks(client, options.hooks, {
    block: "webhook-inbox",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
