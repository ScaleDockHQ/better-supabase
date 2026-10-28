import type { ResolvedConfig } from "../config/index.ts";
import type { BlockSqlContext } from "./context.ts";

import { moduleLayout } from "./layout.ts";
import { moduleContext } from "./module-context.ts";
import { manyRoles } from "./modules/membership-roles.ts";
import { SQL_MODULES } from "./registry.ts";

/**
 * One block table as the config names it: unquoted schema and table, and each
 * logical column's written name, or `null` when an adopted table lacks it.
 */
export interface BlockTable<Column extends string = string> {
  readonly schema: string;
  readonly name: string;
  /** `schema.name`, unquoted. */
  readonly table: string;
  readonly columns: { readonly [K in Column]: string | null };
}

/** The membership and tenant tables an authorization library reads. */
export interface BlockTables {
  /** `blocks.memberships`: one row per member of a tenant. */
  readonly memberships?: BlockTable<"tenant" | "user" | "role" | "disabledAt">;
  /** `membership_roles`, with `blocks.memberships.options.roles.many`. */
  readonly membershipRoles?: BlockTable<"tenant" | "user" | "role">;
  /** `blocks.organizations`: the tenants. */
  readonly organizations?: BlockTable<
    "id" | "name" | "slug" | "disabledAt" | "deletedAt"
  >;
  /**
   * Every installed block instance, by instance name, then logical table. A
   * table the config maps to `null` is left out.
   */
  readonly byBlock: Readonly<
    Record<string, Readonly<Record<string, BlockTable>>>
  >;
}

function tableOf<Column extends string>(
  ctx: BlockSqlContext,
  logical: string,
  columns: readonly Column[],
): BlockTable<Column> {
  const { schema, name } = ctx.tableName(logical);

  const written = Object.fromEntries(
    columns.map((column) => [
      column,
      ctx.has(logical, column) ? ctx.colName(logical, column) : null,
    ]),
  );

  // SAFETY: `written` has one entry per element of `columns`.
  const typed = written as { readonly [K in Column]: string | null };

  return { schema, name, table: `${schema}.${name}`, columns: typed };
}

function tablesOf(ctx: BlockSqlContext): Record<string, BlockTable> {
  const specs = SQL_MODULES[ctx.module]?.names?.tables ?? {};

  return Object.fromEntries(
    Object.entries(specs)
      .filter(([logical]) => ctx.hasTable(logical))
      .map(([logical, spec]) => [
        logical,
        tableOf(ctx, logical, Object.keys(spec.columns)),
      ]),
  );
}

/**
 * The block tables `config` installs, with `blocks.<name>.tables` and
 * `blocks.<name>.columns` renames resolved the way the rendered SQL resolves
 * them (`ctx.table` and `ctx.col`). An authorization library reads its
 * membership and tenant tables from here instead of hard-coding the defaults.
 */
export function blockTables(config: ResolvedConfig): BlockTables {
  const layout = moduleLayout(config);
  const installed = Object.keys(config.blocks);
  const byBlock: Record<string, Readonly<Record<string, BlockTable>>> = {};
  const contexts = new Map<string, BlockSqlContext>();

  for (const [name, instance] of Object.entries(config.instances)) {
    if (!SQL_MODULES[instance.block]?.names) {
      continue;
    }

    const ctx = moduleContext(instance.block, layout, installed, name);
    byBlock[name] = tablesOf(ctx);

    if (name === instance.block) {
      contexts.set(name, ctx);
    }
  }

  const members = contexts.get("memberships");
  const tenants = contexts.get("organizations");

  const membershipRoles =
    members && manyRoles(members)
      ? {
          schema: members.schemaName,
          name: "membership_roles",
          table: `${members.schemaName}.membership_roles`,
          columns: {
            tenant: members.colName("memberships", "tenant"),
            user: members.colName("memberships", "user"),
            role: "role",
          },
        }
      : undefined;

  return {
    ...(members
      ? {
          memberships: tableOf(members, "memberships", [
            "tenant",
            "user",
            "role",
            "disabledAt",
          ]),
        }
      : {}),
    ...(membershipRoles ? { membershipRoles } : {}),
    ...(tenants
      ? {
          organizations: tableOf(tenants, "organizations", [
            "id",
            "name",
            "slug",
            "disabledAt",
            "deletedAt",
          ]),
        }
      : {}),
    byBlock,
  };
}
