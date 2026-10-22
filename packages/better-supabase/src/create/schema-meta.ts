import type { BlockSqlTableSpec } from "../sql/index.ts";
import type { SchemaData, SchemaSoftRef, SchemaTable } from "./schema.ts";

import { PRESET_CATALOG } from "../preset/index.ts";
import { SQL_MODULES } from "../sql/index.ts";

const AUTH_USERS = "auth.users";

/**
 * The tenant name the module defaults use, which a preset's tenant name
 * replaces.
 */
const DEFAULT_TENANT = "organization";

type TableLookup = (module: string, name: string) => SchemaTable | undefined;

/**
 * Finds the parsed table for a module's logical table by its default name, or
 * by that name with the tenant renamed (`organizations` is `workspaces` for the
 * `workspace` tenant).
 */
function indexTables(
  tables: readonly SchemaTable[],
  tenantName: string,
): TableLookup {
  const byName = new Map(
    tables.map((table) => [`${table.module}:${table.name}`, table]),
  );

  return (module, name) =>
    byName.get(`${module}:${name}`) ??
    byName.get(`${module}:${name.replaceAll(DEFAULT_TENANT, tenantName)}`);
}

function moduleTables(
  module: string,
): readonly (readonly [string, BlockSqlTableSpec])[] {
  return Object.entries(SQL_MODULES[module]?.names?.tables ?? {});
}

/**
 * The table the tenant columns point at: the target most foreign keys on a
 * tenant column share. `null` when no table has a tenant foreign key.
 */
function tenantTable(tables: readonly SchemaTable[]): string | null {
  const counts = new Map<string, number>();

  for (const table of tables) {
    for (const key of table.foreignKeys) {
      if (
        table.tenantColumn !== null &&
        key.columns.length === 1 &&
        key.columns[0] === table.tenantColumn
      ) {
        const to = `${key.target.schema}.${key.target.table}`;
        counts.set(to, (counts.get(to) ?? 0) + 1);
      }
    }
  }

  let best: string | null = null;
  let most = 0;

  for (const [id, count] of counts) {
    if (count > most) {
      best = id;
      most = count;
    }
  }

  return best;
}

/**
 * The physical column a logical lifecycle column maps to. A tenant name renames
 * `organization_id`, so a default name the table lacks falls back to the
 * table's tenant column.
 */
function physicalColumn(
  table: SchemaTable,
  name: string | undefined,
  tenant: boolean,
): string | undefined {
  if (name === undefined) {
    return undefined;
  }

  if (table.columns.some((column) => column.name === name)) {
    return name;
  }

  return tenant && table.tenantColumn !== null ? table.tenantColumn : undefined;
}

function hasForeignKey(table: SchemaTable, column: string): boolean {
  return table.foreignKeys.some(
    (key) => key.columns.length === 1 && key.columns[0] === column,
  );
}

/**
 * The soft references in the tables: lifecycle tenant and user columns without
 * a foreign key, and `regclass` columns, which name any table.
 */
function softReferences(
  tables: readonly SchemaTable[],
  tenantName: string = DEFAULT_TENANT,
): readonly SchemaSoftRef[] {
  const lookup = indexTables(tables, tenantName);
  const tenantTo = tenantTable(tables);
  const refs: SchemaSoftRef[] = [];
  const seen = new Set<string>();

  const add = (ref: SchemaSoftRef): void => {
    const key = `${ref.from}.${ref.column}`;

    if (!seen.has(key)) {
      seen.add(key);
      refs.push(ref);
    }
  };

  for (const block of new Set(tables.map((table) => table.module))) {
    for (const [, spec] of moduleTables(block)) {
      const table = lookup(block, spec.name);
      const lifecycle = spec.lifecycle;

      if (table === undefined || lifecycle === undefined) {
        continue;
      }

      const tenant = physicalColumn(
        table,
        lifecycle.tenant === undefined
          ? undefined
          : spec.columns[lifecycle.tenant],
        true,
      );

      if (
        tenant !== undefined &&
        tenantTo !== null &&
        tenantTo !== table.id &&
        !hasForeignKey(table, tenant)
      ) {
        add({ from: table.id, column: tenant, to: tenantTo, kind: "tenant" });
      }

      const user = physicalColumn(
        table,
        lifecycle.user === undefined ? undefined : spec.columns[lifecycle.user],
        false,
      );

      if (user !== undefined && !hasForeignKey(table, user)) {
        add({ from: table.id, column: user, to: AUTH_USERS, kind: "user" });
      }
    }
  }

  for (const table of tables) {
    for (const column of table.columns) {
      if (column.type.toLowerCase() === "regclass") {
        add({ from: table.id, column: column.name, to: null, kind: "any" });
      }
    }
  }

  return refs;
}

const MANIFEST_BY_MODULE = new Map(
  PRESET_CATALOG.blocks.map((block) => [block.name, block.manifest]),
);

const EXTRA_TABLE_BY_MODULE = new Map(
  PRESET_CATALOG.blocks.flatMap((block) =>
    block.extraColumns === undefined ? [] : [[block.name, block.extraColumns]],
  ),
);

/** Each table's module and logical table name. */
function blockTables(
  tables: readonly SchemaTable[],
  lookup: TableLookup,
): SchemaData["blockTables"] {
  return Object.fromEntries(
    tables.flatMap((table) => {
      const logical = moduleTables(table.module).find(
        ([, spec]) => lookup(table.module, spec.name) === table,
      )?.[0];

      return logical === undefined
        ? []
        : [[table.id, { block: table.module, table: logical }]];
    }),
  );
}

/** The table ids `blocks.<module>.options.extraColumns` adds columns to. */
function extraColumnTables(
  tables: readonly SchemaTable[],
  lookup: TableLookup,
): readonly string[] {
  const installed = new Set(tables.map((table) => table.module));

  return [...EXTRA_TABLE_BY_MODULE].flatMap(([module, logical]) => {
    const spec = SQL_MODULES[module]?.names?.tables[logical];

    const table =
      !installed.has(module) || spec === undefined
        ? undefined
        : lookup(module, spec.name);

    return table === undefined ? [] : [table.id];
  });
}

/**
 * The tables plus the soft references, manifests and extra-column tables the
 * canvas draws.
 */
export function schemaData(
  tables: readonly SchemaTable[],
  tenantName: string = DEFAULT_TENANT,
): SchemaData {
  const lookup = indexTables(tables, tenantName);

  return {
    tables,
    softRefs: softReferences(tables, tenantName),
    manifests: Object.fromEntries(
      tables.map((table) => [
        table.id,
        MANIFEST_BY_MODULE.get(table.module) ?? table.module,
      ]),
    ),
    extraColumns: extraColumnTables(tables, lookup),
    blockTables: blockTables(tables, lookup),
    tenantTable: tenantTable(tables),
  };
}
