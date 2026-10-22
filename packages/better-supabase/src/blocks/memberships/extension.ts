import type {
  HasFlag,
  Plugin,
  RepositoryExtension,
  RequestContext,
} from "../../core/plugin.ts";
import type { MutationOp, Operation } from "../../ir/types.ts";
import type { SchemaMeta, TableMeta } from "../../schema/types.ts";

import { tenantFrom, tenantPathsFor } from "../../core/claims.ts";
import { DbException, dbError } from "../../core/errors.ts";
import { definePlugin, spansAllTenants } from "../../core/plugin.ts";
import { scopeOperation } from "../../ir/scope.ts";
import { dbName, equals, forbidden, insertsOnly } from "../extension-shared.ts";

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

/**
 * `C` is the claims type (`betterSupabase.claims(schema)`'s output); it types
 * `claim`.
 */
export interface MembershipsExtensionOptions<C = unknown> {
  /**
   * JWT claim path(s) holding the tenant id when `context.tenant` is not set.
   * Dots walk into objects. Defaults to `config.auth.organization.claim`
   * (`tenant_id`), then the same key in `app_metadata`. `user_metadata` is
   * never a source: users can write it.
   */
  readonly claim?: ClaimPath<C> | readonly ClaimPath<C>[];
  /** Custom resolution, e.g. from a header validated against memberships. */
  readonly resolve?: (context: RequestContext) => string | undefined;
  /**
   * What happens on a tenant table without an organization in the context:
   * `skip` (default) leaves it to RLS; `error` fails with `forbidden`.
   */
  readonly onMissing?: "error" | "skip";
  /**
   * The request header `resolve` reads the tenant from. The plugin does not
   * read it; `defineApi` documents it as a parameter of tenant tables.
   */
  readonly header?: string;
}

export interface MembershipsFindArgs {
  /**
   * Skip the tenant filter for this call (admin tooling, jobs). RLS still
   * applies.
   */
  readonly allTenants?: boolean;
}

export interface MembershipsExtension extends RepositoryExtension {
  readonly findArgs: HasFlag<this["M"], this["T"], "tenant"> extends true
    ? MembershipsFindArgs
    : unknown;
  readonly methods: unknown;
  readonly deleteArgs: HasFlag<this["M"], this["T"], "tenant"> extends true
    ? MembershipsFindArgs
    : unknown;
}

/**
 * The tenant for a request: `context.tenant`, then the configured claim.
 * `schema` supplies the default claim (`config.claims.tenant`).
 */
export function resolveOrganization<C = unknown>(
  context: RequestContext,
  options: MembershipsExtensionOptions<C> = {},
  schema?: Pick<SchemaMeta, "claims">,
): string | undefined {
  if (options.resolve) {
    return options.resolve(context);
  }

  // SAFETY: MembershipsExtensionOptions types claim as ClaimPath<C> or a list of them, and
  // both are strings at runtime.
  const claim = options.claim as string | readonly string[] | undefined;

  return tenantFrom(context, tenantPathsFor(claim, schema));
}

/** Tenant columns may be numeric; the resolved tenant is always a string. */
function sameTenant(value: unknown, id: string): boolean {
  if (value === id) {
    return true;
  }

  return (
    (typeof value === "number" || typeof value === "bigint") &&
    String(value) === id
  );
}

function tenantColumn(table: TableMeta): string | undefined {
  return dbName(table, table.flags.tenant);
}

/**
 * The `memberships` block's repository extension, for tables generated with
 * `Flags.tenant`. Scopes reads, updates and deletes to the request's
 * organization (nested includes and relation filters too), fills the
 * organization column on insert and rejects writes that would move rows to
 * another organization. It complements RLS; it does not replace it. `gen`
 * installs it with `auth.organization`; `.use()` it again to replace it.
 */
export function membershipsExtension<C = unknown>(
  options: MembershipsExtensionOptions<C> = {},
): Plugin<"tenant", MembershipsExtension> {
  const onMissing = options.onMissing ?? "skip";
  /** A context is fixed for a connection, so its tenant is resolved once. */
  const resolved = new WeakMap<RequestContext, string | undefined>();

  const resolvedFor = (
    context: RequestContext,
    schema: SchemaMeta,
  ): string | undefined => {
    let id = resolved.get(context);

    if (id === undefined && !resolved.has(context)) {
      id = resolveOrganization(context, options, schema);
      resolved.set(context, id);
    }

    return id;
  };

  const missing = (table: TableMeta): never => {
    throw new DbException(
      dbError(
        "forbidden",
        `No tenant in the request context for "${table.key}"`,
      ),
    );
  };

  const current = (
    table: TableMeta,
    context: RequestContext,
    schema: SchemaMeta,
  ): string | undefined => {
    const id = resolvedFor(context, schema);

    if (id === undefined && onMissing === "error" && tenantColumn(table)) {
      missing(table);
    }

    return id;
  };

  return definePlugin<"tenant", MembershipsExtension>({
    name: "tenant",
    scopes: ["tenant"],
    describe(api): void {
      for (const { table } of api.resources) {
        const flag = table.flags.tenant;

        if (!flag) {
          continue;
        }

        api.markReadOnly(table.key, flag, "Set from the request's tenant.");

        if (options.header) {
          api.addParameter(table.key, {
            name: options.header,
            in: "header",
            required: onMissing === "error",
            description: "The tenant the request acts for.",
            schema: { type: "string" },
          });
        }
      }
    },
    context(context, { schema }): RequestContext {
      if (spansAllTenants(context)) {
        return context;
      }

      const id = resolvedFor(context, schema);

      if (id === undefined || id === context.tenant) {
        return context;
      }

      const derived = { ...context, tenant: id };
      resolved.set(derived, id);

      return derived;
    },
    transformQuery(op, { context, schema, options: call }): Operation {
      if (call["allTenants"] === true || spansAllTenants(context)) {
        return op;
      }

      const id = resolvedFor(context, schema);

      if (id === undefined) {
        if (onMissing === "error") {
          scopeOperation(op, (table) =>
            tenantColumn(table) ? missing(table) : undefined,
          );
        }

        return op;
      }

      return scopeOperation(op, (table) => {
        const column = tenantColumn(table);

        return column ? equals(column, id) : undefined;
      });
    },
    beforeMutation(op, { table, context, schema, options: call }): MutationOp {
      const column = tenantColumn(table);

      if (!column || call["allTenants"] === true || spansAllTenants(context)) {
        return op;
      }

      const id = current(table, context, schema);

      if (id === undefined) {
        return op;
      }

      switch (op.kind) {
        case "insert": {
          if (!insertsOnly(op) && !op.onConflict?.columns.includes(column)) {
            forbidden(
              `An upsert on ${table.key} that updates on conflict needs the tenant column "${column}" in its conflict target`,
            );
          }

          return {
            ...op,
            rows: op.rows.map((row) => {
              if (column in row && !sameTenant(row[column], id)) {
                forbidden(`Cannot write a ${table.key} row for another tenant`);
              }

              return { ...row, [column]: id };
            }),
          };
        }

        case "update": {
          if (column in op.set && !sameTenant(op.set[column], id)) {
            forbidden(`Cannot move a ${table.key} row to another tenant`);
          }

          return op;
        }

        case "delete": {
          return op;
        }

        default: {
          const exhaustive: never = op;

          return exhaustive;
        }
      }
    },
  });
}
