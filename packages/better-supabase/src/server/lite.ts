import type { ResolveAuthOptions } from "../auth/resolve.ts";
import type { BetterSupabaseEnv } from "../env/index.ts";

/** The `[db] driver` values Supabase Lite reads from `supabase/config.toml`. */
export type LiteDriver = "sqlite-postgres" | "sqlite" | "pglite" | "postgres";

/** Lite's default driver, the one `lite init` scaffolds. */
const DEFAULT_LITE_DRIVER: LiteDriver = "sqlite-postgres";

/** Whether the driver stores data in SQLite, where Lite has no database functions. */
function isSqliteDriver(driver: LiteDriver): boolean {
  switch (driver) {
    case "sqlite-postgres":
    case "sqlite": {
      return true;
    }
    case "pglite":
    case "postgres": {
      return false;
    }
    default: {
      const exhaustive: never = driver;
      return exhaustive;
    }
  }
}

function liteRpcUnavailable(driver: LiteDriver): string {
  return `rpc() is not available on Supabase Lite with the ${driver} driver. Set [db] driver = "pglite" or "postgres" in supabase/config.toml, or call an HTTP endpoint instead.`;
}

type AuthOptions = Omit<ResolveAuthOptions, "env">;

export interface LiteBackendOptions {
  readonly backend?: "supabase" | "lite";
  readonly liteDriver?: LiteDriver;
  readonly postgres?: unknown;
  readonly auth?: AuthOptions;
}

export interface LiteBackend {
  /** `options.auth` with the Lite secret from `SUPABASE_JWT_SECRET`. */
  auth(): AuthOptions;
  /** The `unsupported` message for `rpc()`, on Lite's SQLite drivers. */
  readonly rpcUnavailable: string | undefined;
}

/** What `backend: "lite"` changes in `createServer`; `undefined` for Supabase. */
export function liteBackend(
  options: LiteBackendOptions,
  env: () => BetterSupabaseEnv,
): LiteBackend | undefined {
  if (options.backend !== "lite") {
    return undefined;
  }
  const driver = options.liteDriver ?? DEFAULT_LITE_DRIVER;
  if (options.postgres && driver !== "postgres") {
    throw new TypeError(
      `Supabase Lite with the ${driver} driver has no Postgres connection for ctx.sql. Remove the postgres option, or run Lite with [db] driver = "postgres".`,
    );
  }
  return {
    auth() {
      if (options.auth?.jwtSecret !== undefined) {
        return options.auth;
      }
      const jwtSecret = env().jwtSecret;
      if (jwtSecret === undefined) {
        throw new TypeError(
          'backend: "lite" needs SUPABASE_JWT_SECRET, the auth.jwt_secret Supabase Lite signs user tokens with',
        );
      }
      return { ...options.auth, jwtSecret };
    },
    rpcUnavailable: isSqliteDriver(driver)
      ? liteRpcUnavailable(driver)
      : undefined,
  };
}
