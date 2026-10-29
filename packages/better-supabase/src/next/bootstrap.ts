import type { AuthSession } from "../auth/view.ts";
import type { Executor } from "../core/executor.ts";
import type { Bootstrap } from "./types.ts";

import { DbException, dbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";

/**
 * One bootstrap wrapper's answer: the session flag, the authz versions, the
 * tenant and the data.
 */
export interface BootstrapRow {
  readonly sessionActive: boolean;
  /**
   * The live version when the database keeps one, else the token's. A wrapper
   * generated before 0.40 returns the token's.
   */
  readonly authzVersion: number | null;
  /** The `authz_ver` claim of the token the query ran with. */
  readonly tokenAuthzVersion: number | null;
  readonly tenant: string | null;
  readonly data: unknown;
}

/**
 * The schema a `bsb.bootstrap()` call targets: the call's, then
 * `bootstrapSchema`, then the one `gen` recorded, else `better_supabase`.
 */
export function bootstrapSchema(
  call: { readonly schema?: string | undefined },
  options: { readonly bootstrapSchema?: string | undefined },
  owner: {
    readonly meta: {
      readonly bootstrap?: { readonly schema: string } | undefined;
    };
  },
): string {
  return (
    call.schema ??
    options.bootstrapSchema ??
    owner.meta.bootstrap?.schema ??
    "better_supabase"
  );
}

/** A caller without a session: no wrapper call, nothing to cache. */
export function signedOutBootstrap<C, P>(
  view: AuthSession<C, P>,
  tenant: string | undefined,
): Bootstrap<C, P, never> {
  return {
    session: view,
    tenant: tenant ?? null,
    authzVersion: null,
    tokenAuthzVersion: null,
    stale: false,
    sessionActive: false,
    data: null,
  };
}

/** Calls `<schema>.bootstrap_<rpc>(args)` and checks the row it returns. */
export async function runBootstrap(
  executor: Executor,
  schema: string,
  rpc: string,
  args: Readonly<Record<string, unknown>>,
): Promise<BootstrapRow> {
  if (!executor.rpc) {
    throw new DbException(
      dbError(
        "unsupported",
        "bsb.bootstrap() needs an executor that calls functions",
      ),
    );
  }

  const result = await executor.rpc(
    `bootstrap_${rpc}`,
    { args },
    { schema, errorMappers: [] },
  );

  if (!result.ok) {
    throw new DbException(result.error);
  }

  return bootstrapRow(result.data);
}

/** The wrapper's jsonb, checked: a row the wrapper didn't write throws. */
function bootstrapRow(value: unknown): BootstrapRow {
  if (!isRecord(value) || typeof value["session_active"] !== "boolean") {
    throw new DbException(
      dbError("unexpected", "The bootstrap wrapper returned no session_active"),
    );
  }

  const tenant = value["tenant"];
  const authzVersion = versionOf(value["authz_version"]);

  return {
    sessionActive: value["session_active"],
    authzVersion,
    tokenAuthzVersion:
      "token_authz_version" in value
        ? versionOf(value["token_authz_version"])
        : authzVersion,
    tenant: typeof tenant === "string" ? tenant : null,
    data: value["data"] ?? null,
  };
}

/** A version as jsonb returns it: a number, or a bigint as a digit string. */
function versionOf(value: unknown): number | null {
  if (typeof value === "number") {
    return value;
  }

  return typeof value === "string" && /^\d+$/.test(value)
    ? Number(value)
    : null;
}
