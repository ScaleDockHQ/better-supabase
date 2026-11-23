import type { FileFacts } from "./schema-reader/index.ts";

import { factsOf, statementsOf } from "./schema-reader/index.ts";
import {
  declaredTableColumns,
  indexStatements,
} from "./schema-reader/queries.ts";

/** A column a block adds to a table the app owns, with its statement. */
export interface OwnedColumn {
  /** `schema.table`, unquoted. */
  readonly table: string;
  readonly column: string;
  /** The block's `alter table ... add column if not exists ...;` statement. */
  readonly statement: string;
}

/** A block object an app object of the same table already covers. */
export interface DuplicateObject {
  readonly kind: "index" | "trigger";
  /** `schema.table`. */
  readonly table: string;
  /** The block's index or trigger. */
  readonly block: string;
  /** The app's index, or the app's call that creates the trigger. */
  readonly app: string;
  /**
   * `identical` for the same keys, `weaker` for a unique key the app's narrower
   * one implies.
   */
  readonly reason: "identical" | "weaker" | "same-work";
}

/**
 * The columns the rendered block files add with `add column if not exists` to a
 * table the app's own files create, when those files declare no such column.
 * Today the block adds them to the app's table; a later release leaves them
 * out, which turns the feature off, so the app's files should declare them (ADR
 * 0325). The caller awaits `primeSchemaFacts` and `primeStatements` for both
 * lists first.
 *
 * @param rendered - The block files.
 * @param appFiles - The app's schema files.
 * @param schemas - The schemas the app owns.
 * @returns One entry per column, in render order.
 */
export function ownedColumns(
  rendered: readonly { readonly contents: string }[],
  appFiles: readonly { readonly text: string }[],
  schemas: readonly string[],
): readonly OwnedColumn[] {
  const appFacts = appFiles.map((file) => factsOf(file.text));
  const declared = declaredTableColumns(appFacts, schemas);
  const added = new Map<string, Set<string>>();

  for (const facts of appFacts) {
    for (const alter of facts.alters) {
      const set = added.get(alter.table) ?? new Set<string>();

      for (const column of alter.addedColumns) {
        set.add(column.name);
      }

      added.set(alter.table, set);
    }
  }

  const seen = new Set<string>();
  const found: OwnedColumn[] = [];

  for (const file of rendered) {
    const facts = factsOf(file.contents);
    const statements = statementsOf(file.contents);

    for (const alter of facts.alters) {
      const column = alter.addedIfNotExists[0];

      if (column === undefined) {
        continue;
      }

      const key = `${alter.table}.${column}`;

      if (
        !declared.has(alter.table) ||
        declared.get(alter.table)!.has(column) ||
        added.get(alter.table)?.has(column) === true ||
        seen.has(key)
      ) {
        continue;
      }

      const statement = statements.find((entry) => entry.line === alter.line);

      if (statement === undefined) {
        continue;
      }

      seen.add(key);
      found.push({
        table: alter.table,
        column,
        statement: `${statement.text};`,
      });
    }
  }

  return found;
}

const sameSet = (a: readonly string[], b: readonly string[]): boolean =>
  a.length === b.length && a.every((column) => b.includes(column));

const NOT_NULL_KEY = /^(?:"([^"]+)"|([A-Za-z_][\w$]*))\s+is\s+not\s+null$/i;

/** A unique btree key, including `where <column> is not null` and no expression. */
function countsAsKey(
  index: ReturnType<typeof indexStatements>[number],
): boolean {
  if (!index.unique || !index.plain || index.method !== "btree") {
    return false;
  }

  if (!index.partial) {
    return true;
  }

  const text = (index.where ?? "")
    .trim()
    .replace(/^where\s+/i, "")
    .replace(/^\(+/, "")
    .replace(/\)+$/, "")
    .trim();

  const match = NOT_NULL_KEY.exec(text);
  const column = match?.[1] ?? match?.[2];

  return column !== undefined && index.columns.includes(column);
}

const withSchema = (name: string): string =>
  name.includes(".") ? name : `public.${name}`;

/**
 * The indexes and triggers a block's files create on a table where the app's
 * files already make the same, or a stricter, guarantee: a unique index whose
 * columns are the same as, or a subset of, the block's unique key, and an
 * `updated_at` trigger the app creates with `track_updated_at()` next to a
 * block trigger that sets it. A partial unique index whose `where` is exactly
 * `<key column> is not null` counts as the full key. An expression key does
 * not. Both run on every write, or index every row, for nothing. The caller
 * awaits `primeSchemaFacts` for both lists first.
 *
 * @param blockFiles - The block files.
 * @param appFiles - The app's schema files.
 * @param schemas - The schemas the app owns.
 * @returns The covered block objects.
 */
export function duplicateObjects(
  blockFiles: readonly { readonly contents: string }[],
  appFiles: readonly { readonly text: string }[],
  schemas: readonly string[],
): readonly DuplicateObject[] {
  const inSchemas = (table: string): boolean =>
    schemas.includes(table.slice(0, table.indexOf(".")));

  const app: FileFacts[] = appFiles.map((file) => factsOf(file.text));
  const block: FileFacts[] = blockFiles.map((file) => factsOf(file.contents));
  const found: DuplicateObject[] = [];

  const appIndexes = app
    .flatMap((facts) => indexStatements(facts))
    .filter(countsAsKey);

  for (const index of block.flatMap((facts) => indexStatements(facts))) {
    if (!countsAsKey(index) || !inSchemas(index.table)) {
      continue;
    }

    const covering = appIndexes.find(
      (other) =>
        other.table === index.table &&
        other.columns.every((column) => index.columns.includes(column)),
    );

    if (covering !== undefined) {
      found.push({
        kind: "index",
        table: index.table,
        block: index.name ?? index.columns.join(", "),
        app: covering.name ?? covering.columns.join(", "),
        reason: sameSet(covering.columns, index.columns)
          ? "identical"
          : "weaker",
      });
    }
  }

  const tracked = new Set(
    app.flatMap((facts) =>
      facts.calls.flatMap((call) =>
        call.name.split(".").at(-1) === "track_updated_at" &&
        call.strings[0] !== undefined
          ? [withSchema(call.strings[0])]
          : [],
      ),
    ),
  );

  for (const facts of block) {
    for (const trigger of facts.triggers) {
      if (trigger.timing === "instead of") {
        continue;
      }

      const name = trigger.name;

      if (
        tracked.has(trigger.table) &&
        inSchemas(trigger.table) &&
        /updated_at/i.test(trigger.function) &&
        name !== "bsb_updated_at"
      ) {
        found.push({
          kind: "trigger",
          table: trigger.table,
          block: name,
          app: `track_updated_at('${trigger.table}')`,
          reason: "same-work",
        });
      }
    }
  }

  return found;
}
