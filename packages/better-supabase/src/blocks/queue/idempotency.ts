import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { BlockProblemOptions } from "../../core/problem.ts";
import type { SqlClient } from "../../postgres/executor.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { JobHandler } from "./types.ts";

import { leaseHeartbeat } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { problemResponse } from "../../core/problem.ts";
import { periodSeconds } from "../../core/ratelimit-headers.ts";
import { AsyncResult } from "../../core/result.ts";
import { applyTemporal, blockCall, run, seconds } from "../shared.ts";
import { transportRows } from "./backends.ts";

/**
 * Where `createIdempotency` stores keys: a transport, or a service SQL
 * connection.
 */
export type IdempotencySource =
  | {
      /**
       * A service-role transport, such as `rpcTransport(adminClient, { schema:
       * "api" })` over the wrappers `blocks.idempotency.api` writes.
       */
      readonly transport: BlockTransport;
      readonly sql?: never;
    }
  | {
      /** A service SQL connection: `postgres.admin` or `ctx.postgresAdmin`. */
      readonly sql: SqlClient;
      readonly transport?: never;
    };

export type IdempotencyOptions = IdempotencySource & IdempotencySettings;

export interface IdempotencySettings
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
  /**
   * Answer 400 when the header is missing. Defaults to false (run without a
   * key).
   */
  readonly required?: boolean;
  /** Defaults to `Idempotency-Key`. */
  readonly header?: string;
  /**
   * The schema the functions live in, over a transport. Defaults to
   * `better_supabase`.
   */
  readonly schema?: string;
  /** Error mappers that run before the built-in ones, over a transport. */
  readonly mappers?: readonly ErrorMapper[];
  /**
   * `withBlockHooks` hooks around `begin`, `extend`, `complete`, `release` and
   * `purge`.
   */
  readonly hooks?: BlockHooks<Idempotency>;
  /** Receives the errors `after` hooks throw. */
  readonly logger?: Logger;
}

export type IdempotencyState = "started" | "replay" | "running" | "mismatch";

export interface Idempotency {
  /**
   * Runs `handler` at most once per key: retries with the same key and body get
   * the stored response (with `Idempotency-Replayed: true`).
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
   * Moves the lock of a running key `lock` further for `holder`. `false` once
   * the lock ran out or another caller took the key over. `handle` calls it at
   * half the lock while the handler runs.
   */
  extend(key: string, holder: string, scope?: string): AsyncResult<boolean>;
  /**
   * Stores the response for `holder`. `false` when the lock ran out and another
   * caller took the key over, so the response was not stored.
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
  /** Deletes expired keys (`purge_idempotency_keys`); returns how many. */
  purge(): AsyncResult<number>;
  /** A job handler that runs `purge`; schedule it hourly. */
  purgeJob(): JobHandler<unknown>;
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
    .toSorted();

  const credential = authorization ?? cookies.join(";");

  return credential === "" ? "" : `caller:${await sha256(credential)}`;
}

interface StoredResponse {
  readonly body: string;
  readonly contentType: string | null;
}

interface BeginRow {
  readonly state: IdempotencyState;
  readonly status_code: number | null;
  readonly response: unknown;
  readonly holder: string | null;
}

/** The calls `createIdempotency` makes, over SQL or a transport. */
interface IdempotencyCalls {
  begin(
    scope: string,
    key: string,
    fingerprint: string,
    ttl: string,
    lock: string,
  ): AsyncResult<BeginRow | undefined>;
  complete(
    scope: string,
    key: string,
    holder: string,
    status: number,
    body: unknown,
  ): AsyncResult<boolean>;
  extend(
    scope: string,
    key: string,
    holder: string,
    lock: string,
  ): AsyncResult<boolean>;
  release(scope: string, key: string, holder: string): AsyncResult<boolean>;
  purge(): AsyncResult<number>;
}

function sqlCalls(sql: SqlClient): IdempotencyCalls {
  return {
    begin: (scope, key, fingerprint, ttl, lock) =>
      run(async () => {
        const [row] = await sql.queryRaw<BeginRow>(
          "select * from better_supabase.begin_idempotent($1, $2, $3, $4::interval, $5::interval)",
          [scope, key, fingerprint, ttl, lock],
        );

        return row;
      }),
    complete: (scope, key, holder, status, body) =>
      run(async () => {
        const [row] = await sql.queryRaw<{ done: boolean }>(
          "select better_supabase.complete_idempotent($1, $2, $3, $4, $5) as done",
          [scope, key, holder, status, JSON.stringify(body)],
        );

        return row?.done === true;
      }),
    extend: (scope, key, holder, lock) =>
      run(async () => {
        const [row] = await sql.queryRaw<{ done: boolean }>(
          "select better_supabase.extend_idempotent($1, $2, $3, $4::interval) as done",
          [scope, key, holder, lock],
        );

        return row?.done === true;
      }),
    release: (scope, key, holder) =>
      run(async () => {
        const [row] = await sql.queryRaw<{ done: boolean }>(
          "select better_supabase.release_idempotent($1, $2, $3) as done",
          [scope, key, holder],
        );

        return row?.done === true;
      }),
    purge: () =>
      run(async () => {
        const [row] = await sql.queryRaw<{ purged: number }>(
          "select better_supabase.purge_idempotency_keys() as purged",
        );

        return row?.purged ?? 0;
      }),
  };
}

function transportCalls(
  transport: BlockTransport,
  schema: string | undefined,
  mappers: readonly ErrorMapper[] | undefined,
): IdempotencyCalls {
  const call = blockCall(transport, schema, mappers);

  return {
    begin: (scope, key, fingerprint, ttl, lock) =>
      call(
        "begin_idempotent",
        { scope, key, request_hash: fingerprint, ttl, lock },
        (value) => transportRows<BeginRow>("begin_idempotent", value)[0],
      ),
    complete: (scope, key, holder, status, body) =>
      call(
        "complete_idempotent",
        { scope, key, holder, status_code: status, response: body },
        (value) => value === true,
      ),
    extend: (scope, key, holder, lock) =>
      call(
        "extend_idempotent",
        { scope, key, holder, lock },
        (value) => value === true,
      ),
    release: (scope, key, holder) =>
      call(
        "release_idempotent",
        { scope, key, holder },
        (value) => value === true,
      ),
    purge: () =>
      call("purge_idempotency_keys", {}, (value) => Number(value ?? 0)),
  };
}

/**
 * HTTP idempotency keys (IETF `Idempotency-Key` header) over the `idempotency`
 * SQL module: a service SQL connection, or a service-role `rpcTransport` over
 * the wrappers `blocks.idempotency.api` writes.
 */
export function createIdempotency(options: IdempotencyOptions): Idempotency {
  applyTemporal(options);
  const headerName = options.header ?? "idempotency-key";
  const format = options.problem;
  const ttl = seconds(options.ttl ?? "24 hours");
  const lock = seconds(options.lock ?? "1 minute");
  // An interval periodSeconds can't read renews every second.
  const lockSeconds = periodSeconds(options.lock ?? 60) ?? 2;

  const calls =
    options.transport === undefined
      ? sqlCalls(options.sql)
      : transportCalls(options.transport, options.schema, options.mappers);

  const client: Idempotency = {
    purge: () => calls.purge(),
    purgeJob: () => async () => hooked.purge().orThrow(),
    begin: (key, fingerprint, scope = "") =>
      calls
        .begin(scope, key, fingerprint, ttl, lock)
        .andThen((row) =>
          row
            ? AsyncResult.ok({
                state: row.state,
                status: row.status_code,
                body: row.response,
                holder: row.holder ?? undefined,
              })
            : AsyncResult.err(
                dbError("unexpected", "begin_idempotent returned no row"),
              ),
        ),
    extend: (key, holder, scope = "") => calls.extend(scope, key, holder, lock),
    complete: (key, holder, status, body, scope = "") =>
      calls.complete(scope, key, holder, status, body),
    release: (key, holder, scope = "") => calls.release(scope, key, holder),
    async handle(request, handler) {
      const key = request.headers.get(headerName);
      const url = new URL(request.url);
      const instance = url.pathname;

      if (!key) {
        return options.required
          ? problemResponse(
              dbError(
                "invalid_request",
                `The ${headerName} header is required`,
                { code: "IDEMPOTENCY_KEY_MISSING" },
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
        `${request.method} ${instance}${url.search}\n${body}`,
      );

      const started = await hooked.begin(key, fingerprint, scope);

      if (!started.ok) {
        return problemResponse(started.error, { instance, format });
      }

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

        case "running": {
          return problemResponse(
            dbError(
              "conflict",
              "A request with this idempotency key is still running",
              { code: "IDEMPOTENCY_KEY_IN_USE" },
            ),
            { instance, format, headers: { "retry-after": "1" } },
          );
        }

        case "mismatch": {
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
        }

        case "started": {
          break;
        }

        default: {
          const unknown: never = state;
          throw new TypeError(`Unknown idempotency state ${String(unknown)}`);
        }
      }

      let renewing = true;

      const stopHeartbeat = leaseHeartbeat(lockSeconds, () => {
        if (!renewing) {
          return;
        }

        void hooked.extend(key, holder, scope).then((extended) => {
          if (extended.ok && !extended.data) {
            // Another request holds the key now; complete returns false.
            renewing = false;
          }

          return extended;
        });
      });

      try {
        let response: Response;

        try {
          response = await handler(request);
        } catch (cause) {
          await hooked.release(key, holder, scope);
          throw cause;
        }

        if (response.status >= 500) {
          await hooked.release(key, holder, scope);

          return response;
        }

        const stored: StoredResponse = {
          body: await response.clone().text(),
          contentType: response.headers.get("content-type"),
        };

        const completed = await hooked.complete(
          key,
          holder,
          response.status,
          stored,
          scope,
        );

        if (!completed.ok || !completed.data) {
          // The lock expired and another request took the key, or the store
          // failed: this response was never saved, so a retry must not be
          // told it was.
          return problemResponse(
            completed.ok
              ? dbError(
                  "conflict",
                  "The idempotency key's lock expired before the response was saved",
                  { code: "IDEMPOTENCY_KEY_LOST" },
                )
              : completed.error,
            { instance, format, headers: { "retry-after": "1" } },
          );
        }

        return response;
      } finally {
        stopHeartbeat();
      }
    },
  };

  const hooked = withBlockHooks(client, options.hooks, {
    block: "idempotency",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}

// ---------------------------------------------------------------------------
// Leases (SQL module `idempotency`)
