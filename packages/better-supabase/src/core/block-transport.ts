import type { SqlClient } from "../postgres/executor.ts";
import type { ErrorMapper, RawDbError } from "./errors.ts";
import type { Executor } from "./executor.ts";

import { encodeArguments } from "../ir/wire.ts";
import { DbException } from "./db-exception.ts";
import { isRecord } from "./guards.ts";
import { sqlIdent } from "./template.ts";

/**
 * Calls a block function as the current user and resolves with its result.
 * Rejects with the raw database error (a `pg` error or a PostgREST error
 * object), which the block maps to a `DbError`.
 */
export interface BlockTransport {
  call(
    schema: string,
    fn: string,
    args: Readonly<Record<string, unknown>>,
  ): Promise<unknown>;
}

/**
 * Calls the functions over Postgres, as the user `client` runs as:
 * `sqlTransport(postgres.asUser(ctx.auth.claims))`. Works for any schema.
 */
export function sqlTransport(client: SqlClient): BlockTransport {
  return {
    async call(schema, fn, args) {
      const entries = Object.entries(encodeArguments(args));

      // pg sends an array as a Postgres array literal; an array of objects
      // is a jsonb argument, so it goes as JSON.
      const params = entries.map(([, value]) =>
        value !== null &&
        typeof value === "object" &&
        (!Array.isArray(value) ||
          value.some((entry) => entry !== null && typeof entry === "object"))
          ? JSON.stringify(value)
          : value,
      );

      const list = entries
        .map(([name], index) => `${sqlIdent(name)} => $${String(index + 1)}`)
        .join(", ");

      const [row] = await client.queryRaw<{ value: unknown }>(
        `select ${sqlIdent(schema)}.${sqlIdent(fn)}(${list}) as value`,
        params,
      );

      return row?.value ?? null;
    },
  };
}

interface RpcResponse {
  readonly data: unknown;
  readonly error: unknown;
}

/**
 * The part of a supabase-js client `rpcTransport` uses. The parameters are
 * `never` so a typed `SupabaseClient<Database>` fits too: its `schema` and
 * `rpc` only take the names its `Database` declares, which never include the
 * block functions of a schema the types leave out.
 */
export interface RpcClient {
  schema(name: never): {
    rpc(fn: never, args: never): PromiseLike<RpcResponse>;
  };
}

/** How `rpcTransport` calls the client: any schema, function and arguments. */
interface UntypedRpcClient {
  schema(name: string): {
    rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResponse>;
  };
}

/** Options for `rpcTransport`. */
export interface RpcTransportOptions {
  /**
   * The exposed schema that holds the block's entry points, such as `api` from
   * `blocks.<module>.api`. Every call goes there instead of the module schema,
   * which stays out of `[api] schemas` (doctor BS312).
   */
  readonly schema?: string;
}

/**
 * Calls the functions over the Data API with the user's session. Pass `schema`
 * with the API schema that `blocks.<module>.api` writes wrappers into; without
 * it the calls go to the module schema, which then has to be exposed.
 */
export function rpcTransport(
  client: RpcClient,
  options: RpcTransportOptions = {},
): BlockTransport {
  // Method parameters are bivariant, so the never parameters widen back.
  const untyped: UntypedRpcClient = client;

  return {
    async call(schema, fn, args) {
      const { data, error } = await untyped
        .schema(options.schema ?? schema)
        .rpc(fn, encodeArguments(args));

      if (error) {
        const message =
          typeof error === "object" && "message" in error
            ? String(error.message)
            : String(error);

        throw Object.assign(new Error(message), error);
      }

      return data;
    },
  };
}

/** Options for `dbTransport`. */
export interface DbTransportOptions {
  /**
   * The schema every call goes to instead of the module schema, such as the API
   * schema from `blocks.<module>.api`. Over PostgREST it has to be exposed;
   * over Postgres any schema the caller may use works.
   */
  readonly schema?: string;
}

/** The part of a `Db` that `dbTransport` uses. */
export interface DbTransportSource {
  readonly $executor: Executor;
}

/**
 * Calls the functions through a `Db`'s executor, so a block runs wherever the
 * `Db` does: over PostgREST for `ctx.db` in a normal request, and over direct
 * Postgres as the target in a support session or for an API key. Rejects with
 * the raw database error, like the other transports, so the block's error
 * mappers see the same codes and hints.
 */
export function dbTransport(
  db: DbTransportSource,
  options: DbTransportOptions = {},
): BlockTransport {
  return {
    async call(schema, fn, args) {
      const executor = db.$executor;

      if (!executor.rpc) {
        throw new TypeError(
          `dbTransport needs an executor with rpc(); the ${executor.name} executor has none`,
        );
      }

      let raw: RawDbError | undefined;

      const capture: ErrorMapper = (error) => {
        raw = error;

        return;
      };

      const result = await executor.rpc(fn, encodeArguments(args), {
        schema: options.schema ?? schema,
        errorMappers: [capture],
      });

      if (result.ok) {
        return result.data;
      }

      if (raw === undefined) {
        throw new DbException(result.error);
      }

      throw Object.assign(new Error(raw.message ?? result.error.message), raw);
    },
  };
}

/** The Postgres or PostgREST error a transport rejected with, if it is one. */
export function rawError(cause: unknown): RawDbError | undefined {
  if (!isRecord(cause)) {
    return undefined;
  }

  const field = (key: string): string | undefined => {
    const value = cause[key];

    return typeof value === "string" ? value : undefined;
  };

  if (field("code") === undefined) {
    return undefined;
  }

  const raw: Record<string, string> = {};

  for (const key of ["message", "code", "details", "hint", "constraint"]) {
    const value = field(key);

    if (value !== undefined) {
      raw[key] = value;
    }
  }

  // pg names it `detail`; PostgREST, `details`.
  const detail = field("detail");

  if (raw["details"] === undefined && detail !== undefined) {
    raw["details"] = detail;
  }

  return raw;
}
