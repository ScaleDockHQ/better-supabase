import type { AuthState, SessionRejection } from "../auth/resolve.ts";
import type { AuthSession } from "../auth/view.ts";
import type {
  AnyAuthorizer,
  AuthzSubjectSeed,
  AuthzVersionCache,
} from "../core/authorizer.ts";
import type { BootstrapPermissions } from "../core/bootstrap-permissions.ts";
import type { Executor } from "../core/executor.ts";
import type {
  InferReadSetParams,
  ReadSet,
  ReadSetResult,
} from "../core/read-set.ts";
import type { AsyncResult } from "../core/result.ts";
import type { SchemaMeta } from "../schema/types.ts";

import { sessionCacheKey, snapshotOf } from "../auth/snapshot.ts";
import { tenantOf, toSession } from "../auth/view.ts";
import { bindAuthorizer } from "../core/authorizer.ts";
import { expandBootstrapPermissions } from "../core/bootstrap-permissions.ts";
import { TEAM_IDS_TRUNCATED_CLAIM } from "../core/claim-names.ts";
import { claimsOf } from "../core/claims.ts";
import { DbException, dbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";
import { authorizeCaller } from "./kit.ts";

/** One `bootstrap_<rpc>` call: the parts every adapter takes. */
export interface BootstrapCallOptions<S extends ReadSet = ReadSet> {
  /**
   * The name in `blocks.sessions.options.bootstrap`; the call runs
   * `bootstrap_<rpc>` in the sessions schema (its API schema when there is
   * one).
   */
  readonly rpc: string;
  /** Passed to the app's function as its one `jsonb` argument. */
  readonly args?: Readonly<Record<string, unknown>>;
  /**
   * The schema to call. Defaults to `ServerOptions.bootstrapSchema`, then the
   * schema `gen` records for the sessions block, else `better_supabase`.
   */
  readonly schema?: string;
  /** The active tenant. Defaults to the token's tenant claim. */
  readonly tenant?: string;
  /**
   * A read set to run with the session check, in the same query. It must be
   * listed in `blocks.sessions.options.bootstrap[rpc].readSets`. When another
   * call of the same request already ran the wrapper, only the read set runs.
   * The answer is `Bootstrap.reads`.
   */
  readonly readSet?: S;
  /** The read set's parameters. */
  readonly params?: InferReadSetParams<S>;
}

/** What a bootstrap call returns: plain data, safe across a cache boundary. */
export interface Bootstrap<
  C = unknown,
  P = unknown,
  T = unknown,
  R = Readonly<Record<string, unknown>>,
> {
  readonly session: AuthSession<C, P>;
  readonly tenant: string | null;
  /**
   * The caller's live authorization version when the database keeps one
   * (`blocks.sessions.options.authzVersions` or `authorization.versions`), else
   * the token's.
   */
  readonly authzVersion: number | null;
  /** The `authz_ver` claim of the caller's access token. */
  readonly tokenAuthzVersion: number | null;
  /**
   * The live version is ahead of the token's: permissions changed after the
   * token was issued. The next refresh picks them up; a client
   * `SessionProvider` refreshes on the broadcast.
   */
  readonly stale: boolean;
  readonly sessionActive: boolean;
  /**
   * Why `sessionActive` is false: `user_banned` or `session_not_found`. Null
   * while the session is active or signed out. A wrapper generated before 0.44
   * returns no reason and is refused: run `bsb sql upgrade`.
   */
  readonly endReason: SessionRejection | null;
  readonly data: T | null;
  /**
   * The read set's result, decoded like `db.$many(readSet, params)`; null
   * without one.
   */
  readonly reads?: R | null;
  /**
   * The authorizer subject, when
   * `blocks.sessions.options.bootstrap[rpc].subject` names a function.
   * `accessFor` seeds it into the authorizer's runtime.
   */
  readonly subject?: unknown;
  /**
   * The tenant `subject` is restricted to, when the provider sets
   * `subjectForTenant` and the call named a tenant; null when the subject
   * covers every tenant. `accessFor` copies it into the seed.
   */
  readonly subjectTenant?: string | null;
  /**
   * The caller's permissions, when the provider sets
   * `authorization.functions.bootstrapPermissions`: expanded from either wire
   * form (`BootstrapPermissionsWire`). Null when the provider returns none, or
   * a value this version does not understand (another `apiVersion`, a damaged
   * bitset), so the page falls back to its authorizer.
   */
  readonly permissions?: BootstrapPermissions | null;
  /**
   * The token's `team_ids` is not the user's whole team list (the hook set
   * `team_ids_truncated`), so a team check must ask the database. False when
   * the claim is absent.
   */
  readonly teamIdsTruncated?: boolean;
}

/** One context and its checks, bound to one authorization version. */
export interface Access<Ctx, C = unknown, P = unknown, Ref = string> {
  readonly context: Ctx;
  readonly session: AuthSession<C, P>;
  readonly tenant: string | null;
  readonly authzVersion: number | null;
  /** Whether the caller holds `permission` in the tenant; `false` signed out. */
  can(permission: Ref): Promise<boolean>;
}

/**
 * One bootstrap wrapper's answer: the session flag, the authz versions, the
 * tenant and the data.
 */
export interface BootstrapRow {
  readonly sessionActive: boolean;
  /** The wrapper's `end_reason` when the session isn't active. */
  readonly endReason: SessionRejection | null;
  /**
   * The live version when the database keeps one, else the token's. A wrapper
   * generated before 0.40 returns the token's.
   */
  readonly authzVersion: number | null;
  /** The `authz_ver` claim of the token the query ran with. */
  readonly tokenAuthzVersion: number | null;
  readonly tenant: string | null;
  readonly data: unknown;
  /** The wrapper's raw `reads` payload, from the read set it ran. */
  readonly reads: unknown;
  /** The authorizer subject the wrapper's `subject` function returned. */
  readonly subject: unknown;
  /**
   * The wrapper's `subject_tenant`; undefined for a wrapper generated before it
   * existed.
   */
  readonly subjectTenant?: string | null;
  /** The wrapper's raw `permissions` payload, in either wire form. */
  readonly permissions?: unknown;
}

/**
 * The schema a bootstrap call targets: the call's, then `bootstrapSchema`, then
 * the one `gen` recorded, else `better_supabase`.
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
function signedOutBootstrap<C, P, R>(
  view: AuthSession<C, P>,
  tenant: string | undefined,
): Bootstrap<C, P, never, R> {
  return {
    session: view,
    tenant: tenant ?? null,
    authzVersion: null,
    tokenAuthzVersion: null,
    stale: false,
    sessionActive: false,
    endReason: null,
    data: null,
    reads: null,
  };
}

/** Calls `<schema>.bootstrap_<rpc>(args)` and checks the row it returns. */
async function runBootstrap(
  executor: Executor,
  schema: string,
  rpc: string,
  args: Readonly<Record<string, unknown>>,
  readSet?: { readonly name: string; readonly params: unknown },
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
    readSet
      ? { args, read_set: readSet.name, read_params: readSet.params ?? {} }
      : { args },
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

  const sessionActive = value["session_active"];
  const reason = value["end_reason"];

  const ended =
    reason === "user_banned" || reason === "session_not_found" ? reason : null;

  if (!sessionActive && ended === null) {
    throw new DbException(
      dbError(
        "unexpected",
        "The bootstrap wrapper returned no end_reason; it was generated before 0.44. Run `bsb sql upgrade` and apply the migration.",
      ),
    );
  }

  return {
    sessionActive,
    endReason: sessionActive ? null : ended,
    authzVersion,
    tokenAuthzVersion:
      "token_authz_version" in value
        ? versionOf(value["token_authz_version"])
        : authzVersion,
    tenant: typeof tenant === "string" ? tenant : null,
    data: value["data"] ?? null,
    reads: value["reads"] ?? null,
    subject: value["subject"] ?? null,
    ...("subject_tenant" in value
      ? {
          subjectTenant:
            typeof value["subject_tenant"] === "string"
              ? value["subject_tenant"]
              : null,
        }
      : {}),
    permissions: value["permissions"] ?? null,
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

/** What `bootstrapWith` needs from the server. */
export interface BootstrapDeps {
  readonly schema: (call: BootstrapCallOptions) => string;
  readonly evictSession: (userId: string) => Promise<void>;
  readonly versions: AuthzVersionCache | undefined;
  /**
   * The claim set to `true` when `team_ids` is not the user's whole list.
   * Defaults to `team_ids_truncated`.
   */
  readonly teamIdsTruncatedClaim?: string;
  /** Called with the caller's access token when the session ended. */
  readonly onEnded?: (token: string, reason: SessionRejection) => void;
}

/**
 * Shares one wrapper call among the callers with the same key, such as the
 * loaders of one page.
 */
export type BootstrapMemo = ((
  key: string,
  run: () => Promise<BootstrapRow>,
) => Promise<BootstrapRow>) & {
  /** Whether a call with `key` is already memoized. */
  readonly has?: (key: string) => boolean;
};

/** A memo over `calls`: the first call for a key runs, the rest share it. */
export function mapBootstrapMemo(
  calls: Map<string, Promise<BootstrapRow>>,
): BootstrapMemo {
  return Object.assign(
    (key: string, run: () => Promise<BootstrapRow>) => {
      let call = calls.get(key);

      if (!call) {
        call = run();
        calls.set(key, call);
      }

      return call;
    },
    { has: (key: string) => calls.has(key) },
  );
}

/** What `bootstrapWith` needs from the context's `db` to run a read set. */
export interface BootstrapDb {
  readonly $executor: Executor;
  $many(
    readSet: ReadSet,
    params: Readonly<Record<string, unknown>>,
  ): AsyncResult<Record<string, unknown>>;
  $decodeReadSet(
    readSet: ReadSet,
    params: Readonly<Record<string, unknown>>,
    payload: unknown,
  ): AsyncResult<Record<string, unknown>>;
}

/**
 * Runs the bootstrap wrapper for a resolved context. A signed-out caller makes
 * no call. A row with `session_active` false evicts the user; an active one
 * seeds the version cache with the live version.
 */
export async function bootstrapWith<C, P, T, S extends ReadSet = ReadSet>(
  deps: BootstrapDeps,
  ctx: {
    readonly auth: AuthState<C, P>;
    readonly db: BootstrapDb;
    readonly support?: { readonly session: { readonly id: string } };
  },
  call: BootstrapCallOptions<S>,
  tenant: string | undefined,
  memo: BootstrapMemo,
): Promise<Bootstrap<C, P, T, ReadSetResult<S>>> {
  const view = toSession(ctx.auth);
  const snapshot = snapshotOf(ctx.auth);
  const support = ctx.support?.session.id;

  const session =
    support === undefined
      ? snapshot && sessionCacheKey(snapshot)
      : `support:${support}`;

  if (view.kind !== "user" || !session) {
    return signedOutBootstrap(view, tenant);
  }

  const schema = deps.schema(call);
  const args = { ...call.args, ...(tenant ? { tenant } : {}) };
  const shellKey = `${session}|${schema}|${call.rpc}|${JSON.stringify(args)}`;
  const set = call.readSet;
  const params: Readonly<Record<string, unknown>> = call.params ?? {};
  const setKey = set && `${shellKey}|rs:${set.name}|${JSON.stringify(params)}`;

  let row: BootstrapRow;
  // A read set the wrapper didn't run, because the shell was already memoized.
  let separate = false;

  if (set && setKey) {
    if (memo.has?.(setKey)) {
      row = await memo(setKey, () => Promise.reject(new Error("memoized")));
    } else if (memo.has?.(shellKey)) {
      row = await memo(shellKey, () => Promise.reject(new Error("memoized")));
      separate = true;
    } else {
      const first = memo(shellKey, () =>
        runBootstrap(ctx.db.$executor, schema, call.rpc, args, {
          name: set.name,
          params,
        }),
      );

      row = await memo(setKey, () => first);
    }
  } else {
    row = await memo(shellKey, () =>
      runBootstrap(ctx.db.$executor, schema, call.rpc, args),
    );
  }

  if (!row.sessionActive) {
    if (support === undefined) {
      if (ctx.auth.kind === "user") {
        deps.onEnded?.(ctx.auth.token, row.endReason ?? "session_not_found");
      }

      await deps.evictSession(view.user.id);
    }
  } else if (row.authzVersion !== null) {
    await deps.versions?.seed?.(view.user.id, row.authzVersion);
  }

  let reads: unknown = null;

  if (set && row.sessionActive) {
    const decoded = separate
      ? await ctx.db.$many(set, params)
      : row.reads === null
        ? null
        : await ctx.db.$decodeReadSet(set, params, row.reads);

    if (decoded && !decoded.ok) {
      throw new DbException(decoded.error);
    }

    reads = decoded?.data ?? null;
  }

  return {
    session: view,
    sessionActive: row.sessionActive,
    endReason: row.endReason,
    authzVersion: row.authzVersion,
    tokenAuthzVersion: row.tokenAuthzVersion,
    stale:
      row.sessionActive &&
      row.authzVersion !== null &&
      row.tokenAuthzVersion !== null &&
      row.authzVersion > row.tokenAuthzVersion,
    tenant: row.tenant ?? tenant ?? null,
    // SAFETY: the app's function decides the data's type; the wrapper passes its jsonb through.
    data: row.sessionActive ? (row.data as T | null) : null,
    // SAFETY: the decoded payload has the read set's result shape.
    reads: reads as ReadSetResult<S> | null,
    subject: row.sessionActive ? row.subject : null,
    // An older wrapper doesn't say; the call's tenant is the narrow reading.
    subjectTenant: row.sessionActive
      ? row.subjectTenant === undefined
        ? (tenant ?? null)
        : row.subjectTenant
      : null,
    permissions: row.sessionActive
      ? (expandBootstrapPermissions(row.permissions) ?? null)
      : null,
    teamIdsTruncated:
      ctx.auth.kind === "user" &&
      ctx.auth.claims[
        deps.teamIdsTruncatedClaim ?? TEAM_IDS_TRUNCATED_CLAIM
      ] === true,
  };
}

/**
 * The access a context gives: its tenant, its version and a permission check
 * through the server's authorizer.
 */
export function accessOf<
  Ctx extends { readonly auth: AuthState<C, P> },
  C,
  P,
  Ref,
>(
  ctx: Ctx,
  options: {
    readonly tenant: string | null;
    readonly authzVersion: number | null;
    readonly authorizer: AnyAuthorizer | undefined;
    readonly subject?: unknown;
    /** The tenant the subject is restricted to; null for the whole subject. */
    readonly subjectTenant?: string | null;
  },
): Access<Ctx, C, P, Ref> {
  const view = toSession(ctx.auth);

  const seed: AuthzSubjectSeed | undefined =
    view.kind === "user" &&
    options.subject !== undefined &&
    options.subject !== null &&
    options.authzVersion !== null
      ? {
          userId: view.user.id,
          version: options.authzVersion,
          tenant: options.subjectTenant ?? null,
          subject: options.subject,
        }
      : undefined;

  const authorizer = seed
    ? bindAuthorizer(options.authorizer, { seed })
    : options.authorizer;

  return {
    context: ctx,
    session: view,
    tenant: options.tenant,
    authzVersion: options.authzVersion,
    async can(permission) {
      if (view.kind !== "user") {
        return false;
      }

      const outcome = await authorizeCaller(
        ctx.auth,
        { permission },
        undefined,
        options.tenant ?? undefined,
        authorizer,
        ctx,
      );

      return !("kind" in outcome && "message" in outcome);
    },
  };
}

/** A per-Request memo of bootstrap calls, for `server.bootstrapFor`. */
function requestBootstrapMemo(): (request: Request) => BootstrapMemo {
  const calls = new WeakMap<Request, Map<string, Promise<BootstrapRow>>>();

  const byKeyOf = (request: Request): Map<string, Promise<BootstrapRow>> => {
    let byKey = calls.get(request);

    if (!byKey) {
      byKey = new Map();
      calls.set(request, byKey);
    }

    return byKey;
  };

  return (request) =>
    Object.assign(
      (key: string, run: () => Promise<BootstrapRow>) => {
        const byKey = byKeyOf(request);
        let call = byKey.get(key);

        if (!call) {
          call = run();
          byKey.set(key, call);
        }

        return call;
      },
      { has: (key: string) => byKeyOf(request).has(key) },
    );
}

/** The server methods `bootstrapFor` and `accessFor` run on. */
export interface BootstrapServer<Ctx, Snapshot> {
  readonly authorizer: AnyAuthorizer | undefined;
  readonly versions: AuthzVersionCache | undefined;
  evictSession(userId: string): Promise<void>;
  context(
    request: Request,
    options: { readonly tenant?: string },
  ): Promise<Ctx>;
  snapshot(request: Request): Promise<Snapshot | null>;
  contextFromSession(
    snapshot: Snapshot | null,
    options: { readonly tenant?: string },
  ): Promise<Ctx>;
}

/**
 * `bootstrapFor` and `accessFor` for a server. `server` is read on each call,
 * so the server object can be built after them.
 */
export function serverBootstrap<
  Ctx extends { readonly auth: AuthState<C, P>; readonly db: BootstrapDb },
  C,
  P,
  Snapshot extends { readonly authzVersion: number | null },
>(
  owner: { readonly meta: SchemaMeta },
  options: { readonly bootstrapSchema?: string | undefined },
  server: () => BootstrapServer<Ctx, Snapshot>,
): {
  readonly bootstrapFor: <T, S extends ReadSet = ReadSet>(
    request: Request,
    call: BootstrapCallOptions<S>,
  ) => Promise<Bootstrap<C, P, T, ReadSetResult<S>>>;
  readonly accessFor: (
    source: Request | Snapshot | null,
    options?: AccessForOptions<C, P>,
  ) => Promise<Access<Ctx, C, P>>;
} {
  const memo = requestBootstrapMemo();
  const claims = claimsOf(owner.meta);
  const tenantClaim = claims.tenant;

  const teamIdsTruncatedClaim =
    claims.teamIdsTruncated ?? TEAM_IDS_TRUNCATED_CLAIM;

  const scoped = (tenant: string | undefined) =>
    tenant === undefined ? {} : { tenant };

  return {
    bootstrapFor: async (request, call) => {
      const target = server();
      const ctx = await target.context(request, scoped(call.tenant));
      const tenant = call.tenant ?? tenantOf(toSession(ctx.auth), tenantClaim);

      return bootstrapWith(
        {
          schema: (options_) => bootstrapSchema(options_, options, owner),
          evictSession: (userId) => target.evictSession(userId),
          versions: target.versions,
          teamIdsTruncatedClaim,
        },
        ctx,
        call,
        tenant,
        memo(request),
      );
    },
    accessFor: async (source, accessOptions = {}) => {
      const target = server();

      const snapshot =
        source instanceof Request ? await target.snapshot(source) : source;

      const tenant =
        accessOptions.tenant ?? accessOptions.bootstrap?.tenant ?? undefined;

      const ctx = await target.contextFromSession(snapshot, scoped(tenant));

      return accessOf(ctx, {
        tenant: tenant ?? tenantOf(toSession(ctx.auth), tenantClaim) ?? null,
        authzVersion:
          accessOptions.bootstrap?.authzVersion ??
          snapshot?.authzVersion ??
          null,
        authorizer: target.authorizer,
        subject: accessOptions.bootstrap?.subject,
        subjectTenant: accessOptions.bootstrap?.subjectTenant ?? null,
      });
    },
  };
}

export interface AccessForOptions<C = unknown, P = unknown> {
  /** The bootstrap result the page loaded: its tenant and live version. */
  readonly bootstrap?: Bootstrap<C, P>;
  /** The active tenant. Defaults to the bootstrap's, then the token's claim. */
  readonly tenant?: string;
}
