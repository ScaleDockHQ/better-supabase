import type { ResolvedConfig } from "../../config/index.ts";

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** The `schema.function` an entry of `sessions.options.bootstrap` calls, if any. */
function entryFunction(entry: unknown): string | undefined {
  if (typeof entry === "string") {
    return entry;
  }

  if (!isRecord(entry)) {
    return undefined;
  }

  const named = entry["function"] ?? entry["shell"];

  return typeof named === "string" ? named : undefined;
}

/** The sessions block's `bootstrap` entries, or none. */
function entriesOf(config: ResolvedConfig): [string, unknown][] {
  const raw = config.blocks["sessions"]?.options?.["bootstrap"];

  return isRecord(raw) ? Object.entries(raw) : [];
}

/**
 * The functions the sessions block's `bootstrap` entries call, as
 * `schema.name`, so introspection can read their bodies.
 */
export function bootstrapFunctionNames(config: ResolvedConfig): string[] {
  return [
    ...new Set(
      entriesOf(config).flatMap(([, entry]) => entryFunction(entry) ?? []),
    ),
  ];
}

/** A table `gen` knows, by the key the runtime tags it with. */
export interface KnownTable {
  readonly key: string;
  readonly schema: string;
  readonly name: string;
}

const REFERENCE =
  /\b(?:from|join|update|into)\s+(?:only\s+)?(?:"?([a-z_][a-z0-9_]*)"?\.)?"?([a-z_][a-z0-9_]*)"?/gi;

/**
 * The model keys of the known tables a function body reads: a qualified name
 * must match the schema, an unqualified one matches the name in any schema.
 */
function tablesInSource(
  source: string,
  known: readonly KnownTable[],
): string[] {
  const keys = new Set<string>();

  for (const match of source.matchAll(REFERENCE)) {
    const schema = match[1]?.toLowerCase();
    const name = match[2]?.toLowerCase();

    for (const table of known) {
      if (
        table.name === name &&
        (schema === undefined || table.schema === schema)
      ) {
        keys.add(table.key);
      }
    }
  }

  return [...keys];
}

/**
 * The tables each `bootstrap_<rpc>` payload reads: the entry's declared
 * `tables`, else the known tables its function body mentions. An rpc with
 * neither is left out.
 */
export function bootstrapTables(
  config: ResolvedConfig,
  sources: Readonly<Record<string, string>> | undefined,
  known: readonly KnownTable[],
): Record<string, readonly string[]> {
  const tables: Record<string, readonly string[]> = {};

  for (const [rpc, entry] of entriesOf(config)) {
    const declared = isRecord(entry) ? entry["tables"] : undefined;

    if (Array.isArray(declared)) {
      tables[rpc] = declared.filter((table) => typeof table === "string");
      continue;
    }

    const name = entryFunction(entry);
    const source = name === undefined ? undefined : sources?.[name];
    const derived = source === undefined ? [] : tablesInSource(source, known);

    if (derived.length > 0) {
      tables[rpc] = derived;
    }
  }

  return tables;
}
