import type { SchemaReadError } from "./schema-reader/index.ts";
import type { DeclarationSummary } from "./schema-reader/queries.ts";

import {
  factsOf,
  primeCodeStatements,
  primeStatements,
  readSchemaFacts,
  readSchemaFactsLeniently,
} from "./schema-reader/index.ts";
import {
  addedColumnTypes as addedColumnTypesOf,
  declarationsOf,
  declaredColumnTypes as declaredColumnTypesOf,
  declaredForeignKeys as declaredForeignKeysOf,
  declaredIndexes as declaredIndexesOf,
  declaredTableColumns as declaredTableColumnsOf,
  declaredTables as declaredTablesOf,
  declaredUpdatedAtTriggers as declaredUpdatedAtTriggersOf,
  declaredViews as declaredViewsOf,
  extensionSchema as extensionSchemaOf,
  declaredPolicies as declaredPoliciesOf,
  policyGrants as policyGrantsOf,
  rlsTables as rlsTablesOf,
} from "./schema-reader/queries.ts";
import { readSupabaseConfig, tomlGet } from "./supabase-config.ts";

/**
 * The CLI's schema scans, read from the parsed facts of each file. They take
 * the same `{ text }` lists as the text scanners of `better-supabase/sql`, so a
 * caller awaits `primeSchemaFacts` for those texts first. The text scanners
 * stay in `src/sql` for the synchronous render path (ADR 1185).
 */
type Texts = readonly { readonly text: string }[];

const facts = (files: Texts): ReturnType<typeof factsOf>[] =>
  files.map((file) => factsOf(file.text));

/**
 * Reads every file with the parser so the scans below can run synchronously. A
 * file that does not parse throws a `SchemaReadFailure` that names its path.
 *
 * @param files - The SQL files to read.
 * @param root - The project root, for `db.major_version`.
 * @param options - `lenient` keeps empty facts for a file that does not parse.
 * @returns The files that did not parse, empty unless `lenient` is set.
 */
export async function primeSchemaFacts(
  files: readonly { readonly path: string; readonly text: string }[],
  root: string,
  options: { readonly lenient?: boolean } = {},
): Promise<readonly SchemaReadError[]> {
  const toml = await readSupabaseConfig(root);
  const major = toml && tomlGet(toml.document, ["db", "major_version"]);

  const reader = {
    ...(typeof major === "number" ? { majorVersion: major } : {}),
  };

  await primeStatements(
    files.map((file) => file.text),
    reader,
  );

  if (options.lenient === true) {
    return readSchemaFactsLeniently(files, reader);
  }

  await readSchemaFacts(files, reader);

  return [];
}

/**
 * Reads SQL the CLI generated itself (module bodies), so a scan or
 * `withoutComments` can run on it synchronously. A text that does not parse
 * keeps empty facts: generated text is checked where it is rendered.
 *
 * @param texts - The generated SQL texts.
 */
export async function primeSchemaTexts(
  texts: readonly string[],
): Promise<void> {
  await primeStatements(texts);
  await primeCodeStatements(texts);
  await readSchemaFactsLeniently(
    texts.map((text) => ({ path: "generated.sql", text })),
  );
}

export const declaredTables = (
  files: Texts,
  schemas: readonly string[],
): string[] => declaredTablesOf(facts(files), schemas);

export const declaredColumnTypes = (
  files: Texts,
  schemas: readonly string[],
): ReturnType<typeof declaredColumnTypesOf> =>
  declaredColumnTypesOf(facts(files), schemas);

export const declaredTableColumns = (
  files: Texts,
  schemas: readonly string[],
): ReturnType<typeof declaredTableColumnsOf> =>
  declaredTableColumnsOf(facts(files), schemas);

export const addedColumnTypes = (
  files: Texts,
  schemas: readonly string[],
): ReturnType<typeof addedColumnTypesOf> =>
  addedColumnTypesOf(facts(files), schemas);

export const rlsTables = (files: Texts, schemas: readonly string[]): string[] =>
  rlsTablesOf(facts(files), schemas);

export const declaredViews = (
  files: Texts,
  schemas: readonly string[],
): ReturnType<typeof declaredViewsOf> => declaredViewsOf(facts(files), schemas);

export const policyGrants = (
  files: Texts,
  schemas: readonly string[],
): ReturnType<typeof policyGrantsOf> => policyGrantsOf(facts(files), schemas);

export const declaredPolicies = (
  files: Texts,
  schemas: readonly string[],
): ReturnType<typeof declaredPoliciesOf> =>
  declaredPoliciesOf(facts(files), schemas);

export const extensionSchema = (
  files: Texts,
  extension: string,
): string | undefined => extensionSchemaOf(facts(files), extension);

export const declaredUpdatedAtTriggers = (
  files: Texts,
  schemas: readonly string[],
): ReturnType<typeof declaredUpdatedAtTriggersOf> =>
  declaredUpdatedAtTriggersOf(facts(files), schemas);

export const declaredIndexes = (
  files: Texts,
  schemas: readonly string[],
): ReturnType<typeof declaredIndexesOf> =>
  declaredIndexesOf(facts(files), schemas);

export const declaredForeignKeys = (
  files: Texts,
  schemas: readonly string[],
): ReturnType<typeof declaredForeignKeysOf> =>
  declaredForeignKeysOf(facts(files), schemas);

/** What one primed file declares, in the shape `parseDeclared` returns. */
export const declarationsOfText = (text: string): DeclarationSummary =>
  declarationsOf(factsOf(text));

/**
 * The enum types the files create (`create type ... as enum`), as
 * `schema.type`.
 *
 * @param files - The primed SQL texts.
 * @returns The qualified enum names.
 */
export const declaredEnums = (files: Texts): ReadonlySet<string> =>
  new Set(
    facts(files).flatMap((file) => file.enums.map((entry) => entry.name)),
  );
