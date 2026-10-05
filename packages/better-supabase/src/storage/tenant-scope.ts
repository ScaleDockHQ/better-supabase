import { claimAt, tenantClaimPaths } from "../core/claims.ts";
import { dbError, DbException } from "../core/errors.ts";
import { type RequestContext, spansAllTenants } from "../core/plugin.ts";

export interface TenantScopeOptions {
  readonly context?: RequestContext | undefined;
  readonly tenant?: string | undefined;
  readonly allTenants?: boolean | undefined;
}

/** The checks a tenant bucket's client runs before any Storage call. */
export interface TenantGuard {
  /** Returns `path`, or throws a `forbidden` `DbException` when it isn't the caller's. */
  path<T extends string>(path: T): T;
  readonly param: string;
  /** The tenant a listing under `within` fills in, refusing another tenant's value. */
  within(within: Readonly<Record<string, unknown>> | undefined): string;
}

const forbidden = (bucket: string, message: string): DbException =>
  new DbException(dbError("forbidden", message, { table: bucket }));

function resolveTenant(
  options: TenantScopeOptions,
  claim: string | readonly string[] | undefined,
): string | undefined {
  const { context } = options;
  if (options.tenant !== undefined) return options.tenant;
  if (!context) return undefined;
  if (context.tenant !== undefined) return context.tenant;
  const paths =
    typeof claim === "string" ? [claim] : (claim ?? tenantClaimPaths());
  for (const path of paths) {
    const value = claimAt(context.claims, path);
    if (value !== undefined) return value;
  }
  return undefined;
}

/**
 * The guard for a client of bucket `bucket` whose template holds the tenant
 * in `param`, or `undefined` when nothing is checked (no tenant config,
 * `allTenants`, or an all-tenants context).
 */
export function tenantGuard(
  bucket: string,
  param: string | undefined,
  claim: string | readonly string[] | undefined,
  match: (path: string) => Readonly<Record<string, string | number>> | null,
  options: TenantScopeOptions,
): TenantGuard | undefined {
  const { context } = options;
  if (
    param === undefined ||
    options.allTenants === true ||
    (context && spansAllTenants(context))
  ) {
    return undefined;
  }
  const tenant = resolveTenant(options, claim);
  const tenantOrThrow = (): string => {
    if (tenant !== undefined) return tenant;
    throw forbidden(
      bucket,
      `No tenant for bucket "${bucket}": pass { context } or { tenant } to connect(), or { allTenants: true }`,
    );
  };
  return {
    param,
    path(path) {
      const owner = tenantOrThrow();
      if (String(match(path)?.[param]) !== owner) {
        throw forbidden(bucket, `Path "${path}" belongs to another tenant`);
      }
      return path;
    },
    within(within) {
      const owner = tenantOrThrow();
      const given = within?.[param];
      if (given !== undefined && String(given) !== owner) {
        throw forbidden(bucket, "Listing belongs to another tenant");
      }
      return owner;
    },
  };
}
