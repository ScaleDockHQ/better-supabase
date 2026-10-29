import type {
  AppReference,
  AppTableConfig,
} from "../../config/types/app-tables.ts";
import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";

/**
 * A reference between two tenant-scoped app tables. It becomes a foreign key on
 * `(tenant, column)` to the target's `(tenant, id)`, so a row can't point at a
 * row of another tenant.
 */
export interface TenantReference {
  readonly column: string;
  readonly target: string;
  readonly tenant: string;
  readonly onDelete: AppReference["onDelete"];
}

/** The parts of an app table its tenant references read. */
interface ReferencingTable {
  readonly config: AppTableConfig;
  readonly ctx: BlockSqlContext;
  /** The tenant column, when the table is scoped. */
  readonly scope: { readonly name: string } | undefined;
}

const qualified = (table: string): string =>
  `${sqlIdent("public")}.${sqlIdent(table)}`;

/**
 * The references of a tenant-scoped table to another tenant-scoped app table
 * (itself included), which `tenantKeysSql` checks per tenant.
 */
export function tenantReferencesOf(
  table: ReferencingTable,
  tenantScoped: ReadonlySet<string>,
): ReadonlyMap<string, TenantReference> {
  const references = new Map<string, TenantReference>();

  if (table.ctx.scope.kind !== "tenant" || !table.scope) {
    return references;
  }

  for (const [column, config] of Object.entries(table.config.columns ?? {})) {
    const reference = config.references;

    if (
      reference !== undefined &&
      !("block" in reference) &&
      tenantScoped.has(reference.table)
    ) {
      references.set(column, {
        column,
        target: reference.table,
        tenant: table.scope.name,
        onDelete: reference.onDelete,
      });
    }
  }

  return references;
}

/**
 * The unique `(tenant, id)` index on every target of a tenant reference, then
 * each reference as a foreign key on `(tenant, column)`. The key is dropped and
 * added again so a re-run replaces the single-column key an earlier version
 * wrote under the same name. `set null` names the column (Postgres 15), so the
 * tenant column keeps its value.
 */
export function tenantKeysSql(
  tables: readonly {
    readonly name: string;
    readonly tenantReferences: ReadonlyMap<string, TenantReference>;
  }[],
): string {
  const references = tables.flatMap((table) =>
    [...table.tenantReferences.values()].map((reference) => ({
      table: table.name,
      reference,
    })),
  );

  const targets = new Map(
    references.map(({ reference }) => [reference.target, reference.tenant]),
  );

  const indexes = [...targets].map(
    ([target, tenant]) =>
      `create unique index if not exists ${sqlIdent(`${target}_${tenant}_id_key`)} on ${qualified(target)} (${sqlIdent(tenant)}, id);`,
  );

  const keys = references.map(({ table, reference }) => {
    const name = sqlIdent(`${table}_${reference.column}_fkey`);
    const tenant = sqlIdent(reference.tenant);
    const column = sqlIdent(reference.column);

    const onDelete =
      reference.onDelete === undefined
        ? ""
        : reference.onDelete === "set null"
          ? ` on delete set null (${column})`
          : ` on delete ${reference.onDelete}`;

    return `alter table ${qualified(table)} drop constraint if exists ${name};
alter table ${qualified(table)} add constraint ${name} foreign key (${tenant}, ${column}) references ${qualified(reference.target)} (${tenant}, id)${onDelete};`;
  });

  return [...indexes, ...keys].join("\n");
}
