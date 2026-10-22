import type { AppTableConfig } from "../../config/types/app-tables.ts";

import {
  columnsWithAccess,
  encryptedColumns,
  hiddenColumns,
} from "../../config/app-access.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";

const SCHEMA = "public";

interface AccessTable {
  readonly name: string;
  readonly config: AppTableConfig;
  /** Signed-in users write rows of the table (it has a scope). */
  readonly scoped: boolean;
}

/**
 * Of `names`, the columns signed-in users read: those without `access:
 * "server"` and not encrypted.
 */
export function readableColumns(
  config: AppTableConfig,
  names: readonly string[],
): readonly string[] {
  const hidden = new Set(hiddenColumns(config));

  return names.filter((column) => !hidden.has(column));
}

/** Of `names`, the columns signed-in users write: those without `access`. */
export function writableColumns(
  config: AppTableConfig,
  names: readonly string[],
): readonly string[] {
  const restricted = new Set([
    ...columnsWithAccess(config, "server"),
    ...columnsWithAccess(config, "read"),
  ]);

  return names.filter((column) => !restricted.has(column));
}

function privilege(
  table: AccessTable,
  column: string,
  kind: "SELECT" | "INSERT" | "UPDATE",
  granted: boolean,
): string {
  const label = `${SCHEMA}.${table.name}.${column}`;
  const test = `has_column_privilege('authenticated', ${sqlString(`${sqlIdent(SCHEMA)}.${sqlIdent(table.name)}`)}, ${sqlString(column)}, ${sqlString(kind)})`;
  const verb = kind.toLowerCase();

  return `select extensions.ok(${granted ? test : `not ${test}`}, ${sqlString(`authenticated ${granted ? "may" : "may not"} ${verb} ${label}`)});`;
}

/**
 * The pgTAP checks of the column grants (ADR 0051), run as the superuser:
 * signed-in users read a `read` column but don't write it, and neither read nor
 * write a `server` column. They write an encrypted column (unless its access
 * says otherwise) but never select its ciphertext. Empty without `access` or
 * `encrypted` on any column.
 */
export function columnAccessChecks(table: AccessTable): readonly string[] {
  const readOnly = columnsWithAccess(table.config, "read").filter(
    (column) => table.config.columns?.[column]?.encrypted !== true,
  );

  const hidden = columnsWithAccess(table.config, "server");

  const sealed = encryptedColumns(table.config).filter(
    (column) => !hidden.includes(column),
  );

  return [
    ...readOnly.flatMap((column) => [
      privilege(table, column, "SELECT", true),
      privilege(table, column, "INSERT", false),
      privilege(table, column, "UPDATE", false),
    ]),
    ...hidden.flatMap((column) => [
      privilege(table, column, "SELECT", false),
      privilege(table, column, "INSERT", false),
      privilege(table, column, "UPDATE", false),
    ]),
    ...sealed.flatMap((column) => {
      const writes =
        table.scoped && table.config.columns?.[column]?.access === undefined;

      return [
        privilege(table, column, "SELECT", false),
        privilege(table, column, "INSERT", writes),
        privilege(table, column, "UPDATE", writes),
      ];
    }),
  ];
}

/**
 * The checks run as a signed-in user: selecting a `server` column and, on a
 * table they write, updating a restricted column both fail with 42501. Postgres
 * checks column privileges when it plans the statement, so `where false` still
 * refuses.
 */
export function columnAccessRefusals(table: AccessTable): readonly string[] {
  const target = `${sqlIdent(SCHEMA)}.${sqlIdent(table.name)}`;
  const hidden = hiddenColumns(table.config);

  const restricted = table.scoped
    ? [
        ...columnsWithAccess(table.config, "read"),
        ...columnsWithAccess(table.config, "server"),
      ]
    : [];

  return [
    ...hidden.map(
      (column) =>
        `select extensions.throws_ok($$select ${sqlIdent(column)} from ${target}$$, '42501', null, ${sqlString(`a signed-in user cannot read ${SCHEMA}.${table.name}.${column}`)});`,
    ),
    ...restricted.map(
      (column) =>
        `select extensions.throws_ok($$update ${target} set ${sqlIdent(column)} = null where false$$, '42501', null, ${sqlString(`a signed-in user cannot write ${SCHEMA}.${table.name}.${column}`)});`,
    ),
  ];
}
