import type { SqlClient } from "../postgres/executor.ts";

import { sqlIdent } from "../core/template.ts";

/**
 * Calls a kit function as the current user and resolves with its result.
 * Rejects with the raw database error (a `pg` error or a PostgREST error
 * object), which the kit maps to a `DbError`.
 */
export interface OrgsTransport {
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
export function sqlTransport(client: SqlClient): OrgsTransport {
  return {
    async call(schema, fn, args) {
      const entries = Object.entries(args).filter(
        ([, value]) => value !== undefined,
      );
      const params = entries.map(([, value]) =>
        value !== null && typeof value === "object"
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

/** The part of a supabase-js client `rpcTransport` uses. */
export interface RpcClient {
  schema(name: string): {
    rpc(fn: string, args: Record<string, unknown>): PromiseLike<RpcResponse>;
  };
}

/**
 * Calls the functions over the Data API with the user's session. The kit
 * schema must be exposed (`[api] schemas` in `config.toml`), or the modules
 * installed in `public` (`kits.organizations.schema`).
 */
export function rpcTransport(client: RpcClient): OrgsTransport {
  return {
    async call(schema, fn, args) {
      const defined = Object.fromEntries(
        Object.entries(args).filter(([, value]) => value !== undefined),
      );
      const { data, error } = await client.schema(schema).rpc(fn, defined);
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
