import type { BsbTag } from "./bsb-tags.ts";

import { commentOnTableSql, parseBsbComment, setBsbTag } from "./bsb-tags.ts";

/** The per-table features a `@bsb` tag turns on (ADR 0102). */
export const TABLE_FEATURES = [
  "realtime",
  "audit",
  "audit-reads",
  "subject",
  "json",
  "expose",
  "encrypted",
  "lookup",
  "server",
  "events",
  "vector-search",
  "history",
  "lifecycle",
] as const;

export type TableFeature = (typeof TABLE_FEATURES)[number];

export function isTableFeature(value: string): value is TableFeature {
  return TABLE_FEATURES.some((feature) => feature === value);
}

function escaped(value: string): string {
  return value.replaceAll(/[.*+?^${}()|[\]\\]/gu, String.raw`\$&`);
}

/** `comment on table [schema.]name is '...'` with the quotes `pg-delta` writes. */
function commentPattern(schema: string, table: string): RegExp {
  const name = `(?:"?${escaped(schema)}"?\\.)?"?${escaped(table)}"?`;

  return new RegExp(
    String.raw`comment\s+on\s+table\s+${name}\s+is\s+'((?:[^']|'')*)'\s*;`,
    "iu",
  );
}

/** Whether `sql` creates `table`, in `schema` or unqualified. */
export function createsTable(
  sql: string,
  schema: string,
  table: string,
): boolean {
  const name = `(?:"?${escaped(schema)}"?\\.)?"?${escaped(table)}"?`;

  return new RegExp(
    String.raw`create\s+table\s+(?:if\s+not\s+exists\s+)?${name}\s*\(`,
    "iu",
  ).test(sql);
}

/** The features the table's comment turns on, in `sql`. */
export function tableFeatures(
  sql: string,
  schema: string,
  table: string,
): readonly string[] {
  const match = commentPattern(schema, table).exec(sql);

  return parseBsbComment(match?.[1]?.replaceAll("''", "'") ?? null).tags.map(
    (tag) => tag.name,
  );
}

/**
 * `sql` with the `@bsb` tag `feature` on or off in `table`'s comment. The
 * comment statement is rewritten in place, or appended when the file has none;
 * the free text stays. Returns `sql` unchanged when the feature is already in
 * the wanted state.
 */
export function setTableFeature(
  sql: string,
  schema: string,
  table: string,
  feature: TableFeature,
  enabled: boolean,
  tag?: BsbTag,
): string {
  const pattern = commentPattern(schema, table);
  const match = pattern.exec(sql);
  const current = match?.[1]?.replaceAll("''", "'") ?? null;

  const next = setBsbTag(
    current,
    feature,
    enabled ? (tag ?? { name: feature, args: {} }) : undefined,
  );

  if (match === null) {
    if (!enabled) {
      return sql;
    }

    const separator = sql.endsWith("\n") ? "\n" : "\n\n";

    return `${sql}${separator}${commentOnTableSql(`${schema}.${table}`, next)}\n`;
  }

  if (next === (current ?? "")) {
    return sql;
  }

  return sql.replace(pattern, () =>
    commentOnTableSql(`${schema}.${table}`, next),
  );
}

const ANY_COMMENT =
  /comment\s+on\s+table\s+(?:"?([a-z_][a-z0-9_]*)"?\.)?"?([a-z_][a-z0-9_]*)"?\s+is\s+'((?:[^']|'')*)'\s*;/giu;

/**
 * The `@bsb` table comments in `sql`, with an unqualified table in `public`.
 * Comments without tags are left out.
 */
export function tableTagComments(
  sql: string,
): { schema: string; name: string; comment: string }[] {
  return [...sql.matchAll(ANY_COMMENT)].flatMap((match) => {
    const comment = match[3]?.replaceAll("''", "'");
    const name = match[2];

    return comment !== undefined &&
      name !== undefined &&
      parseBsbComment(comment).tags.length > 0
      ? [{ schema: match[1] ?? "public", name, comment }]
      : [];
  });
}

/**
 * The statement a feature needs besides its tag: `audit` registers the row
 * trigger through a static `audit()` call, which pg-delta keeps in the schema
 * file's diff, and `expose` grants the Data API privileges (row level security
 * still decides the rows). Other features are read from the tag alone.
 */
export function featureStatement(
  feature: TableFeature,
  schema: string,
  table: string,
): string | undefined {
  if (feature === "audit") {
    return `select better_supabase.audit('${schema}.${table}');`;
  }

  return feature === "expose"
    ? `grant select, insert, update, delete on ${schema}.${table} to authenticated;`
    : undefined;
}

/**
 * `sql` with `feature`'s statement present or absent for `table`; `sql` itself
 * when the feature has none or the file is already in the wanted state.
 */
export function setFeatureStatement(
  sql: string,
  schema: string,
  table: string,
  feature: TableFeature,
  enabled: boolean,
): string {
  const statement = featureStatement(feature, schema, table);

  if (statement === undefined) {
    return sql;
  }

  const present = sql.includes(statement);

  if (enabled) {
    return present ? sql : `${sql.replace(/\n*$/u, "")}\n\n${statement}\n`;
  }

  return present
    ? sql.replace(`\n${statement}`, "").replace(statement, "")
    : sql;
}
