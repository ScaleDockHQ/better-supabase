import type { SupabaseClient } from "@supabase/supabase-js";

import type { BetterSupabase } from "../core/define.ts";
import type { SqlClient } from "../postgres/executor.ts";
import type { ServerAudit } from "./audit.ts";
import type { AccountTransport } from "./suspend-account.ts";

import { rpcTransport } from "../core/block-transport.ts";

/**
 * Where a server keeps what `better-supabase/server/account` needs. The account
 * helpers read it from the server they receive, so `createServer` imports none
 * of their code and a route that never deletes an account doesn't bundle it.
 */
export const ACCOUNT_PARTS: unique symbol = Symbol.for(
  "better-supabase.account-parts",
);

export interface AccountParts {
  readonly betterSupabase: Pick<BetterSupabase, "events">;
  readonly service: () => SupabaseClient;
  /** Direct Postgres as the admin role, when `options.postgres` is set. */
  readonly sql: SqlClient | undefined;
  readonly transport: () => AccountTransport;
  readonly audit: ServerAudit;
  /** Runs after an account change; the Next.js server drops the user's caches. */
  readonly after?: (userId: string) => void;
}

/** A server that carries the account parts. */
export interface AccountServer {
  readonly [ACCOUNT_PARTS]: AccountParts;
}

/**
 * Direct Postgres when configured, else the service role over the Data API
 * through the sessions block's API `schema`.
 */
export function accountClient(
  postgres: SqlClient | undefined,
  service: () => SupabaseClient,
  schema: string,
): AccountTransport {
  return postgres ?? rpcTransport(service(), { schema });
}
