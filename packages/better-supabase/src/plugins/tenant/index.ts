import type { MutationOp, Operation } from '../../ir/types.ts';
import type { TableMeta } from '../../schema/types.ts';

import { DbException, dbError } from '../../core/errors.ts';
import {
  definePlugin,
  type HasFlag,
  type Plugin,
  type RepositoryExtension,
  type RequestContext,
} from '../../core/plugin.ts';
import { scopeOperation } from '../../ir/scope.ts';
import { dbName, equals, forbidden } from '../shared.ts';

export interface TenantOptions {
  /**
   * JWT claim path(s) holding the tenant id when `context.tenant` is not set.
   * Dots walk into objects. Default `['org_id', 'app_metadata.org_id']`.
   */
  readonly claim?: string | readonly string[];
  /** Custom resolution, e.g. from a header validated against memberships. */
  readonly resolve?: (context: RequestContext) => string | undefined;
  /**
   * What happens on a tenant table without a tenant in the context:
   * `error` (default) fails with `forbidden`; `skip` leaves it to RLS.
   */
  readonly onMissing?: 'error' | 'skip';
}

export interface TenantFindArgs {
  /** Skip the tenant filter for this call (admin tooling, jobs). RLS still applies. */
  readonly allTenants?: boolean;
}

export interface TenantExtension extends RepositoryExtension {
  readonly findArgs: HasFlag<this['M'], this['T'], 'tenant'> extends true
    ? TenantFindArgs
    : unknown;
  readonly methods: unknown;
  readonly deleteArgs: HasFlag<this['M'], this['T'], 'tenant'> extends true
    ? TenantFindArgs
    : unknown;
}

/** The tenant for a request: `context.tenant`, then the configured claim. */
export function resolveTenant(
  context: RequestContext,
  options: TenantOptions = {},
): string | undefined {
  if (options.resolve) return options.resolve(context);
  if (typeof context.tenant === 'string') return context.tenant;
  const paths =
    typeof options.claim === 'string'
      ? [options.claim]
      : (options.claim ?? DEFAULT_CLAIMS);
  for (const path of paths) {
    let value: unknown = context.claims;
    for (const segment of path.split('.')) {
      value =
        typeof value === 'object' && value !== null
          ? (value as Record<string, unknown>)[segment]
          : undefined;
    }
    if (typeof value === 'string' && value.length > 0) return value;
  }
  return undefined;
}

const DEFAULT_CLAIMS = ['org_id', 'app_metadata.org_id'] as const;

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
export function tenant(
  options: TenantOptions = {},
): Plugin<'tenant', TenantExtension> {
  const onMissing = options.onMissing ?? 'error';

  const current = (
    table: TableMeta,
    context: RequestContext,
  ): string | undefined => {
    const id = resolveTenant(context, options);
    if (id === undefined && onMissing === 'error' && tenantColumn(table)) {
      throw new DbException(
        dbError(
          'forbidden',
          `No tenant in the request context for "${table.key}"`,
        ),
      );
    }
    return id;
  };

  return definePlugin<'tenant', TenantExtension>({
    name: 'tenant',
    transformQuery(op, { context, options: call }): Operation {
      if (call['allTenants'] === true) return op;
      const id = current(op.table, context);
      if (id === undefined) return op;
      return scopeOperation(op, (table) => {
        const column = tenantColumn(table);
        return column ? equals(column, id) : undefined;
      });
    },
    beforeMutation(op, { table, context, options: call }): MutationOp {
      const column = tenantColumn(table);
      if (!column || call['allTenants'] === true) return op;
      const id = current(table, context);
      if (id === undefined) return op;
      switch (op.kind) {
        case 'insert':
          return {
            ...op,
            rows: op.rows.map((row) => {
              if (column in row && row[column] !== id) {
                forbidden(`Cannot write a ${table.key} row for another tenant`);
              }
              return { ...row, [column]: id };
            }),
          };
        case 'update':
          if (column in op.set && op.set[column] !== id) {
            forbidden(`Cannot move a ${table.key} row to another tenant`);
          }
          return op;
        case 'delete':
          return op;
        default: {
          const exhaustive: never = op;
          return exhaustive;
        }
      }
    },
  });
}
