import type { SameTenantLayout } from "../../src/sql/layout-types.ts";

import { adoptedTables, primeAdoption } from "../../src/cli/adopted-columns.ts";
import { ownedColumns, duplicateObjects } from "../../src/cli/block-objects.ts";
import { declaredCheckValues } from "../../src/cli/check-values.ts";
import { sameTenantLayout } from "../../src/cli/same-tenant-layout.ts";
import {
  declaredIndexes,
  declaredTableColumns,
  declaredTables,
  declaredUpdatedAtTriggers,
  primeSchemaTexts,
} from "../../src/cli/sql-facts.ts";
import { writtenValues } from "../../src/cli/written-values.ts";

type Files = readonly { readonly text: string }[];

/**
 * The readers below are synchronous and need the SQL read first. These wrappers
 * read their inputs, then call the reader, so a test keeps its shape.
 */
export const primeAll = (...texts: readonly string[]): Promise<void> =>
  primeSchemaTexts(texts);

export async function sameTenantLayoutOf(
  files: Files,
  schemas: readonly string[],
): Promise<SameTenantLayout> {
  await primeAll(...files.map((file) => file.text));

  return sameTenantLayout(files, schemas);
}

export async function declaredTablesOf(
  files: Files,
  schemas: readonly string[],
): Promise<string[]> {
  await primeAll(...files.map((file) => file.text));

  return declaredTables(files, schemas);
}

export async function declaredTableColumnsOf(
  files: Files,
  schemas: readonly string[],
): Promise<ReturnType<typeof declaredTableColumns>> {
  await primeAll(...files.map((file) => file.text));

  return declaredTableColumns(files, schemas);
}

export async function declaredIndexesOf(
  files: Files,
  schemas: readonly string[],
): Promise<ReturnType<typeof declaredIndexes>> {
  await primeAll(...files.map((file) => file.text));

  return declaredIndexes(files, schemas);
}

export async function declaredUpdatedAtTriggersOf(
  files: Files,
  schemas: readonly string[],
): Promise<ReturnType<typeof declaredUpdatedAtTriggers>> {
  await primeAll(...files.map((file) => file.text));

  return declaredUpdatedAtTriggers(files, schemas);
}

export async function ownedColumnsOf(
  rendered: readonly { readonly contents: string }[],
  app: Files,
  schemas: readonly string[],
): Promise<ReturnType<typeof ownedColumns>> {
  await primeAll(
    ...rendered.map((file) => file.contents),
    ...app.map((file) => file.text),
  );

  return ownedColumns(rendered, app, schemas);
}

export async function duplicateObjectsOf(
  rendered: readonly { readonly contents: string }[],
  app: Files,
  schemas: readonly string[],
): Promise<ReturnType<typeof duplicateObjects>> {
  await primeAll(
    ...rendered.map((file) => file.contents),
    ...app.map((file) => file.text),
  );

  return duplicateObjects(rendered, app, schemas);
}

export async function declaredCheckValuesOf(
  files: Files,
  schemas?: readonly string[],
): Promise<ReturnType<typeof declaredCheckValues>> {
  await primeAll(...files.map((file) => file.text));

  return declaredCheckValues(files, schemas);
}

export async function writtenValuesOf(
  sql: string,
  table: string,
  column: string,
): Promise<readonly string[]> {
  await primeAll(sql);

  return writtenValues(sql, table, column);
}

export async function adoptedTablesOf(
  modules: Parameters<typeof adoptedTables>[0],
  ownTables?: Parameters<typeof adoptedTables>[1],
  views?: Parameters<typeof adoptedTables>[2],
): Promise<ReturnType<typeof adoptedTables>> {
  await primeAdoption(modules, ownTables, views?.subjects);

  return adoptedTables(modules, ownTables, views);
}
