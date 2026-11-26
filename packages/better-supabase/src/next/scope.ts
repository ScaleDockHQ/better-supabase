import type { AuthState } from "../auth/resolve.ts";
import type { AnyAuthorizer } from "../core/authorizer.ts";
import type { DbError } from "../core/errors.ts";
import type { Executor } from "../core/executor.ts";
import type {
  NextOptions,
  NextTenants,
  ScopeCallOptions,
  TenantRecord,
  TenantRef,
} from "./types.ts";

import { err } from "../core/result.ts";
import { accessOf } from "../server/bootstrap.ts";
import { interrupt } from "./control-flow.ts";

const notFound = (message: string): DbError => ({
  kind: "not_found",
  message,
  status: 404,
});

/**
 * Reads a `TenantRef` as a resolver kind and a value: a string takes
 * `NextTenants.by` (default `id`), an object names its own kind.
 */
function readTenantRef(
  ref: TenantRef,
  by: string | undefined,
): { readonly kind: string; readonly value: string } {
  if (typeof ref === "string") {
    return { kind: by ?? "id", value: ref };
  }

  const [entry] = Object.entries(ref);

  if (entry === undefined) {
    return { kind: by ?? "id", value: "" };
  }

  return { kind: entry[0], value: entry[1] };
}

/**
 * The record a ref names. `id` needs no resolver; an unknown kind or a resolver
 * that returns `null` ends the render with `notFound()`.
 */
async function resolveTenantRef(
  ref: TenantRef,
  tenants: NextTenants | undefined,
): Promise<TenantRecord> {
  const { kind, value } = readTenantRef(ref, tenants?.by);
  const resolver = tenants?.resolve[kind];

  if (value === "") {
    interrupt(notFound("No tenant was named."));
  }

  if (resolver === undefined) {
    if (kind === "id") {
      return { id: value };
    }

    throw new TypeError(
      `bsb.tenant(): no resolver for "${kind}"; add it to createNext({ tenants: { resolve } }).`,
    );
  }

  const record = await resolver(value);

  if (record === null) {
    interrupt(notFound("No such tenant."));
  }

  return record;
}

const REFUSALS: Readonly<Record<string, DbError>> = {
  "401": { kind: "unauthorized", message: "Sign in to continue.", status: 401 },
  "403": { kind: "forbidden", message: "Permission denied.", status: 403 },
  "404": { kind: "not_found", message: "No such tenant.", status: 404 },
};

/** The error a refusal interrupt stands for; anything else is rethrown as is. */
function refusalOf(cause: unknown): DbError {
  const digest =
    cause instanceof Error && "digest" in cause ? String(cause.digest) : "";

  const known = REFUSALS[digest.split(";")[1] ?? ""];

  if (known === undefined) {
    throw cause;
  }

  return known;
}

/**
 * An executor whose every call waits for `check`, so a read starts at once
 * under RLS and settles only after the permission check. A refusal settles the
 * read with a `forbidden`, `not_found` or `unauthorized` error.
 */
function gatedExecutor(check: Promise<unknown>) {
  /** Waits for the check; a refusal becomes the error the read settles with. */
  const passed = async (): Promise<DbError | undefined> => {
    try {
      await check;
    } catch (cause) {
      return refusalOf(cause);
    }

    return undefined;
  };

  return (executor: Executor): Executor => ({
    ...executor,
    execute: async (op, context) => {
      const [refusal, result] = await Promise.all([
        passed(),
        executor.execute(op, context),
      ]);

      return refusal === undefined ? result : err(refusal);
    },
    ...(executor.rpc === undefined
      ? {}
      : {
          rpc: async (name, args, context) => {
            const [refusal, result] = await Promise.all([
              passed(),
              // SAFETY: rpc is present, checked above.
              executor.rpc!(name, args, context),
            ]);

            return refusal === undefined ? result : err(refusal);
          },
        }),
    ...(executor.batch === undefined
      ? {}
      : {
          batch: async (ops, context) => {
            const [refusal, results] = await Promise.all([
              passed(),
              // SAFETY: batch is present, checked above.
              executor.batch!(ops, context),
            ]);

            return refusal === undefined
              ? results
              : results.map(() => err(refusal));
          },
        }),
  });
}

/**
 * `bsb.auth`, `bsb.tenant(ref)` and `bsb.activeTenant`, built on `cached` and
 * `require`. They run both at once, and a refused caller never receives the
 * `db`. The members are typed `never` so they take the declared signatures of
 * `BetterNext` where `createNext` spreads them in.
 */
export function scopeMembers(
  getNext: () => {
    readonly cached: (options: never) => Promise<object>;
    readonly require: (options: never) => Promise<object>;
  },
  context: (
    tenant: string | undefined,
  ) => Promise<{ readonly auth: AuthState }>,
  options: NextOptions,
  authorizer: AnyAuthorizer | undefined,
): {
  readonly tenant: never;
  readonly activeTenant: never;
  readonly auth: never;
  readonly shared: never;
} {
  const host = {
    cached: (callOptions: never) => getNext().cached(callOptions),
    requireCaller(callOptions: never): Promise<object> {
      const { require: run } = getNext();

      return run(callOptions);
    },
    context,
    authorizer,
    tenants: options.tenants,
    async rootTenant(): Promise<string | undefined> {
      try {
        return await options.rootParams?.tenant?.();
      } catch {
        return undefined;
      }
    },
  };

  const buildGated = async (
    record: TenantRecord | null,
    permission: unknown,
    cachedOptions: ScopeCallOptions,
  ): Promise<object> => {
    const tenant = record?.id;

    // SAFETY: the options are PrivateCachedOptions without scope and tenant, plus the tenant.
    const scope = (await host.cached({
      ...cachedOptions,
      ...(tenant === undefined ? {} : { tenant }),
    } as never)) as {
      db: { $wrapExecutor: (wrap: (e: Executor) => Executor) => object };
      session: { kind: string; user?: unknown };
    };

    // SAFETY: the options are RequireOptions the declared signature allows.
    const check = host.requireCaller({
      ...(permission === undefined ? {} : { permission }),
      ...(tenant === undefined ? {} : { requireTenant: true, tenant }),
    } as never);

    // A rejection is read by the first read that waits on it.
    check.catch(() => undefined);

    if (scope.session.kind !== "user") {
      await check;
    }

    return Object.defineProperties(
      {},
      {
        ...Object.getOwnPropertyDescriptors(scope),
        db: {
          value: scope.db.$wrapExecutor(gatedExecutor(check)),
          enumerable: true,
        },
        user: { value: scope.session.user, enumerable: true },
        ...(record === null
          ? {}
          : {
              tenant: { value: record, enumerable: true },
              granted: { value: true, enumerable: true },
            }),
        can: {
          value: async (asked: unknown) =>
            accessOf(await host.context(tenant), {
              tenant: tenant ?? null,
              authzVersion: null,
              authorizer: host.authorizer,
            }).can(asked),
          enumerable: true,
        },
      },
    );
  };

  const build = async (
    record: TenantRecord | null,
    permission: unknown,
    scopeOptions: ScopeCallOptions = {},
  ): Promise<object> => {
    const tenant = record?.id;
    const { gate = false, ...cachedOptions } = scopeOptions;

    if (gate) {
      return buildGated(record, permission, cachedOptions);
    }

    const [scope, caller] = await Promise.all([
      // SAFETY: the options are PrivateCachedOptions without scope and tenant, plus the tenant.
      host.cached({
        ...cachedOptions,
        ...(tenant === undefined ? {} : { tenant }),
      } as never),
      // SAFETY: the options are RequireOptions the declared signature allows.
      host.requireCaller({
        ...(permission === undefined ? {} : { permission }),
        ...(tenant === undefined ? {} : { requireTenant: true, tenant }),
      } as never),
    ]);

    // SAFETY: require() refused a caller without a session, so `session` is a user.
    const session = (caller as { session: { user?: unknown } }).session;

    return Object.defineProperties(
      {},
      {
        ...Object.getOwnPropertyDescriptors(scope),
        user: { value: session.user, enumerable: true },
        ...(record === null
          ? {}
          : {
              tenant: { value: record, enumerable: true },
              granted: { value: true, enumerable: true },
            }),
        can: {
          value: async (asked: unknown) =>
            accessOf(await host.context(tenant), {
              tenant: tenant ?? null,
              authzVersion: null,
              authorizer: host.authorizer,
            }).can(asked),
          enumerable: true,
        },
      },
    );
  };

  const forRef = async (
    ref: TenantRef,
    permission: unknown,
    scopeOptions?: ScopeCallOptions,
  ): Promise<object> =>
    build(await resolveTenantRef(ref, host.tenants), permission, scopeOptions);

  // SAFETY: each member has the signature BetterNext declares; see the doc above.
  return {
    tenant: ((
      ref?: TenantRef,
      permission?: unknown,
      scopeOptions?: ScopeCallOptions,
    ) =>
      ref === undefined
        ? host.rootTenant()
        : forRef(ref, permission, scopeOptions)) as never,
    async activeTenant(permission?: unknown, scopeOptions?: ScopeCallOptions) {
      const value = await host.rootTenant();

      if (value === undefined) {
        interrupt(notFound("The route names no tenant."));
      }

      return forRef(value, permission, scopeOptions);
    },
    auth: (permission?: unknown, scopeOptions?: ScopeCallOptions) =>
      build(null, permission, scopeOptions),
    async shared(
      ref: TenantRef,
      permission: unknown,
      read: (tenant: TenantRecord) => Promise<unknown>,
    ) {
      const record = await resolveTenantRef(ref, host.tenants);

      // SAFETY: the options are RequireOptions the declared signature allows.
      await host.requireCaller({
        ...(permission === undefined ? {} : { permission }),
        requireTenant: true,
        tenant: record.id,
      } as never);

      return read(record);
    },
  } as never;
}
