import type { MutationOp, Operation } from "../../ir/types.ts";
import type { SchemaMeta, TableMeta } from "../../schema/types.ts";

import { claimAt, claimsOf, tenantClaimPaths } from "../../core/claims.ts";
import { DbException, dbError } from "../../core/errors.ts";
import {
  definePlugin,
  type HasFlag,
  type Plugin,
  type RepositoryExtension,
  type RequestContext,
} from "../../core/plugin.ts";
import { scopeOperation } from "../../ir/scope.ts";
import { dbName, equals, forbidden } from "../shared.ts";

/**
 * Dotted paths to the string claims of `C` (up to three levels), e.g.
 * `'tenant_id' | 'app_metadata.tenant_id'`. Any string without a claims type.
 */
export type ClaimPath<C> = unknown extends C
  ? string
  : StringPaths<C, [1, 2, 3]>;

type StringPaths<T, Depth extends readonly unknown[]> = T extends object
  ? T extends readonly unknown[]
    ? never
    : {
        [K in keyof T & string]-?:
          | (NonNullable<T[K]> extends string ? K : never)
          | (Depth extends readonly [unknown, ...infer Rest]
              ? `${K}.${StringPaths<NonNullable<T[K]>, Rest>}`
              : never);
      }[keyof T & string]
  : never;

/** `C` is the claims type (`betterSupabase.claims(schema)`'s output); it types `claim`. */
export interface TenantOptions<C = unknown> {
  /**
   * JWT claim path(s) holding the tenant id when `context.tenant` is not set.
   * Dots walk into objects. Defaults to `config.claims.tenant` (`tenant_id`),
   * then the same key in `app_metadata`. `user_metadata` is never a source:
   * users can write it.
   */
  readonly claim?: ClaimPath<C> | readonly ClaimPath<C>[];
  /** Custom resolution, e.g. from a header validated against memberships. */
  readonly resolve?: (context: RequestContext) => string | undefined;
  /**
   * What happens on a tenant table without a tenant in the context:
   * `error` (default) fails with `forbidden`; `skip` leaves it to RLS.
   */
  readonly onMissing?: "error" | "skip";
}

export interface TenantFindArgs {
  /** Skip the tenant filter for this call (admin tooling, jobs). RLS still applies. */
  readonly allTenants?: boolean;
}

export interface TenantExtension extends RepositoryExtension {
  readonly findArgs: HasFlag<this["M"], this["T"], "tenant"> extends true
    ? TenantFindArgs
    : unknown;
  readonly methods: unknown;
  readonly deleteArgs: HasFlag<this["M"], this["T"], "tenant"> extends true
    ? TenantFindArgs
    : unknown;
}

/**
 * The tenant for a request: `context.tenant`, then the configured claim.
 * `schema` supplies the default claim (`config.claims.tenant`).
 */
export function resolveTenant<C = unknown>(
  context: RequestContext,
  options: TenantOptions<C> = {},
  schema?: Pick<SchemaMeta, "claims">,
): string | undefined {
  if (options.resolve) return options.resolve(context);
  if (typeof context.tenant === "string") return context.tenant;
  // SAFETY: TenantOptions types claim as ClaimPath<C> or a list of them, and
  // both are strings at runtime.
  const claim = options.claim as string | readonly string[] | undefined;
  const paths =
    typeof claim === "string"
      ? [claim]
      : (claim ?? tenantClaimPaths(claimsOf(schema).tenant));
  for (const path of paths) {
    const value = claimAt(context.claims, path);
    if (value !== undefined) return value;
  }
  return undefined;
}

function tenantColumn(table: TableMeta): string | undefined {
  return dbName(table, table.flags.tenant);
}

/**
 * Multi-tenancy for tables generated with `Flags.tenant`. Scopes reads,
 * updates and deletes to the request's tenant (nested includes and relation
 * filters too), fills the tenant column on insert and rejects writes that
 * would move rows to another tenant. It complements RLS; it does not replace
 * it.
 */
export function tenant<C = unknown>(
  options: TenantOptions<C> = {},
): Plugin<"tenant", TenantExtension> {
  const onMissing = options.onMissing ?? "error";

  const current = (
    table: TableMeta,
    context: RequestContext,
    schema: SchemaMeta,
  ): string | undefined => {
    const id = resolveTenant(context, options, schema);
    if (id === undefined && onMissing === "error" && tenantColumn(table)) {
      throw new DbException(
        dbError(
          "forbidden",
          `No tenant in the request context for "${table.key}"`,
        ),
      );
    }
    return id;
  };

  return definePlugin<"tenant", TenantExtension>({
    name: "tenant",
    transformQuery(op, { context, schema, options: call }): Operation {
      if (call["allTenants"] === true) return op;
      const id = current(op.table, context, schema);
      if (id === undefined) return op;
      return scopeOperation(op, (table) => {
        const column = tenantColumn(table);
        return column ? equals(column, id) : undefined;
      });
    },
    beforeMutation(op, { table, context, schema, options: call }): MutationOp {
      const column = tenantColumn(table);
      if (!column || call["allTenants"] === true) return op;
      const id = current(table, context, schema);
      if (id === undefined) return op;
      switch (op.kind) {
        case "insert":
          return {
            ...op,
            rows: op.rows.map((row) => {
              if (column in row && row[column] !== id) {
                forbidden(`Cannot write a ${table.key} row for another tenant`);
              }
              return { ...row, [column]: id };
            }),
          };
        case "update":
          if (column in op.set && op.set[column] !== id) {
            forbidden(`Cannot move a ${table.key} row to another tenant`);
          }
          return op;
        case "delete":
          return op;
        default: {
          const exhaustive: never = op;
          return exhaustive;
        }
      }
    },
  });
}
