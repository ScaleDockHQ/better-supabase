import type { BlockTransport } from "../../core/block-transport.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { SqlClient } from "../../postgres/executor.ts";

import { DEFAULT_BLOCK_SCHEMA } from "../../core/block-helpers.ts";
import { dbError } from "../../core/errors.ts";
import {
  problemResponse,
  type BlockProblemOptions,
} from "../../core/problem.ts";
import {
  applyTemporal,
  run,
  seconds,
  type BlockTemporalOptions,
} from "../shared.ts";
import { transportRows } from "./backends.ts";

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
  /** The schema the functions live in, over a transport. Defaults to `better_supabase`. */
  readonly schema?: string;
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

interface BeginRow {
  readonly state: IdempotencyState;
  readonly status_code: number | null;
  readonly response: unknown;
  readonly holder: string | null;
}

/** The three calls `createIdempotency` makes, over SQL or a transport. */
interface IdempotencyCalls {
  begin(
    scope: string,
    key: string,
    fingerprint: string,
    ttl: string,
    lock: string,
  ): Promise<BeginRow | undefined>;
  complete(
    scope: string,
    key: string,
    holder: string,
    status: number,
    body: unknown,
  ): Promise<boolean>;
  release(scope: string, key: string, holder: string): Promise<boolean>;
}

function sqlCalls(sql: SqlClient): IdempotencyCalls {
  return {
    async begin(scope, key, fingerprint, ttl, lock) {
      const [row] = await sql.queryRaw<BeginRow>(
        "select * from better_supabase.begin_idempotent($1, $2, $3, $4::interval, $5::interval)",
        [scope, key, fingerprint, ttl, lock],
      );
      return row;
    },
    async complete(scope, key, holder, status, body) {
      const [row] = await sql.queryRaw<{ done: boolean }>(
        "select better_supabase.complete_idempotent($1, $2, $3, $4, $5) as done",
        [scope, key, holder, status, JSON.stringify(body)],
      );
      return row?.done === true;
    },
    async release(scope, key, holder) {
      const [row] = await sql.queryRaw<{ done: boolean }>(
        "select better_supabase.release_idempotent($1, $2, $3) as done",
        [scope, key, holder],
      );
      return row?.done === true;
    },
  };
}

function transportCalls(
  transport: BlockTransport,
  schema: string,
): IdempotencyCalls {
  return {
    async begin(scope, key, fingerprint, ttl, lock) {
      const [row] = transportRows<BeginRow>(
        "begin_idempotent",
        await transport.call(schema, "begin_idempotent", {
          scope,
          key,
          request_hash: fingerprint,
          ttl,
          lock,
        }),
      );
      return row;
    },
    complete: async (scope, key, holder, status, body) =>
      (await transport.call(schema, "complete_idempotent", {
        scope,
        key,
        holder,
        status_code: status,
        response: body,
      })) === true,
    release: async (scope, key, holder) =>
      (await transport.call(schema, "release_idempotent", {
        scope,
        key,
        holder,
      })) === true,
  };
}

/**
 * HTTP idempotency keys (IETF `Idempotency-Key` header) over the
 * `idempotency` SQL module: a service SQL connection, or a service-role
 * `rpcTransport` over the wrappers `sql.modules.idempotency.api` writes.
 */
export function createIdempotency(
  source: SqlClient | BlockTransport,
  options: IdempotencyOptions = {},
): Idempotency {
  applyTemporal(options);
  const headerName = options.header ?? "idempotency-key";
  const format = options.problem;
  const ttl = seconds(options.ttl ?? "24 hours");
  const lock = seconds(options.lock ?? "1 minute");
  const calls =
    "call" in source
      ? transportCalls(source, options.schema ?? DEFAULT_BLOCK_SCHEMA)
      : sqlCalls(source);

  const begin: Idempotency["begin"] = (key, fingerprint, scope = "") =>
    run(async () => {
      const row = await calls.begin(scope, key, fingerprint, ttl, lock);
      if (!row) throw new TypeError("begin_idempotent returned no row");
      return {
        state: row.state,
        status: row.status_code,
        body: row.response,
        holder: row.holder ?? undefined,
      };
    });
  const complete: Idempotency["complete"] = (
    key,
    holder,
    status,
    body,
    scope = "",
  ) => run(() => calls.complete(scope, key, holder, status, body));
  const release: Idempotency["release"] = (key, holder, scope = "") =>
    run(() => calls.release(scope, key, holder));

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
