import type { BlockSqlFile } from "./module-types.ts";

import { isList, isRecord } from "../core/guards.ts";
import {
  leadingComments,
  maskComments,
  statementSpans,
} from "./over-app-tables.ts";
import { indexStatements } from "./schema-scan.ts";

const INDEX_NAME = /^[a-z_][a-z0-9_]*$/;

function isStringList(value: unknown): value is readonly string[] {
  return isList(value) && value.every((name) => typeof name === "string");
}

const CREATE_INDEX = /^\s*create\s+(?:unique\s+)?index\b/i;

/** `blocks.<instance>.indexes.skip`, or an empty list when the key is absent. */
export function indexSkipOf(block: unknown, where: string): readonly string[] {
  if (!isRecord(block) || block["indexes"] === undefined) {
    return [];
  }

  const indexes = block["indexes"];

  if (
    !isRecord(indexes) ||
    Object.keys(indexes).some((key) => key !== "skip")
  ) {
    throw new TypeError(`${where} must be { skip: ["index_name"] }`);
  }

  const skip = indexes["skip"];

  if (skip === undefined) {
    return [];
  }

  if (!isStringList(skip)) {
    throw new TypeError(`${where}.skip must be a list of index names`);
  }

  for (const name of skip) {
    if (!INDEX_NAME.test(name)) {
      throw new TypeError(
        `${where}.skip: "${name}" is not an index name (lowercase letters, digits and underscores)`,
      );
    }
  }

  return skip;
}

export interface SkippedIndexes {
  readonly sql: string;
  /** Names this text actually dropped. */
  readonly removed: readonly string[];
  /** Every named `create index` in the text, including ones that were dropped. */
  readonly created: readonly string[];
}

/**
 * `sql` without the `create index` statements whose names are in `skip`. A
 * statement that is not itself a `create index` is left alone, so a name that
 * only appears inside a function body is not a created index.
 */
export function withoutSkippedIndexes(
  sql: string,
  skip: ReadonlySet<string>,
): SkippedIndexes {
  if (skip.size === 0) {
    return { sql, removed: [], created: [] };
  }

  const masked = maskComments(sql);

  const removed: string[] = [];
  const created: string[] = [];
  let out = "";
  let cursor = 0;

  for (const [from, to] of statementSpans(sql)) {
    const statement = masked.slice(from, to);

    const named = CREATE_INDEX.test(statement)
      ? indexStatements(statement).flatMap((index) =>
          index.name === undefined ? [] : [index.name],
        )
      : [];

    created.push(...named);

    const drop = named.filter((name) => skip.has(name));

    if (drop.length === 0) {
      continue;
    }

    removed.push(...drop);
    out +=
      sql.slice(cursor, from) + leadingComments(sql.slice(from, to), statement);
    cursor = to;
  }

  return { sql: out + sql.slice(cursor), removed, created };
}

/**
 * Drops each block's skipped indexes from its schema files. A skip name that no
 * schema file of that block creates is an error, with the names it does
 * create.
 */
export function applyIndexSkips(
  files: readonly BlockSqlFile[],
  skipOf: (instance: string) => readonly string[],
): BlockSqlFile[] {
  const pending = new Map<string, Set<string>>();
  const created = new Map<string, Set<string>>();

  const out = files.map((file): BlockSqlFile => {
    const instance = file.instance ?? file.module;
    const skip = skipOf(instance);

    if (skip.length === 0 || file.kind !== "schema") {
      return file;
    }

    const waiting = pending.get(instance) ?? new Set(skip);
    pending.set(instance, waiting);

    const result = withoutSkippedIndexes(file.contents, waiting);
    const names = created.get(instance) ?? new Set<string>();

    for (const name of result.created) {
      names.add(name);
    }

    created.set(instance, names);

    for (const name of result.removed) {
      waiting.delete(name);
    }

    return { ...file, contents: result.sql };
  });

  for (const [instance, left] of pending) {
    if (left.size === 0) {
      continue;
    }

    const known = [...(created.get(instance) ?? [])].toSorted().join(", ");

    throw new TypeError(
      `blocks.${instance}.indexes.skip names ${[...left].join(", ")}, which this module does not create. Indexes: ${known}`,
    );
  }

  return out;
}
