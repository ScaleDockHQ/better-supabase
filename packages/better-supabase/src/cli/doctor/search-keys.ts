import type { SubjectsConfig } from "../../config/index.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { literal } from "./live.ts";

/** One column a search key comparison reads. */
export interface SearchKeyColumn {
  readonly schema: string;
  readonly table: string;
  readonly column: string;
}

/** Two columns a search join or watch compares. */
export interface SearchKeyPair {
  readonly subject: string;
  readonly where: string;
  readonly left: SearchKeyColumn;
  readonly right: SearchKeyColumn;
}

/** A column's type in the live catalog. */
export interface SearchKeyType {
  readonly schema: string;
  readonly table: string;
  readonly column: string;
  readonly type: string;
}

const split = (table: string): SearchKeyColumn & { readonly rest?: never } => {
  const dot = table.indexOf(".");

  return dot === -1
    ? { schema: "public", table, column: "" }
    : { schema: table.slice(0, dot), table: table.slice(dot + 1), column: "" };
};

const columnOf = (table: string, column: string): SearchKeyColumn => ({
  ...split(table),
  column,
});

/**
 * The key pairs search compares: a source view's key against the record id, a
 * watch key against the record id or its `via` column, and each hop.
 */
export function searchKeyPairs(subjects: SubjectsConfig): SearchKeyPair[] {
  const pairs: SearchKeyPair[] = [];

  for (const [type, subject] of Object.entries(subjects)) {
    const search = subject.search;

    if (search === undefined) {
      continue;
    }

    const id = columnOf(subject.table, subject.id ?? "id");

    if (search.from !== undefined) {
      pairs.push({
        subject: type,
        where: `${type} search.from`,
        left: columnOf(search.from.view, search.from.key),
        right: id,
      });
    }

    for (const [index, watched] of (search.watch ?? []).entries()) {
      const key = columnOf(watched.table, watched.key);
      const where = `${type} watch[${String(index)}]`;

      pairs.push({
        subject: type,
        where,
        left: key,
        right:
          watched.via === undefined ? id : columnOf(subject.table, watched.via),
      });

      let previous = key;

      for (const [hopIndex, hop] of (watched.through ?? []).entries()) {
        const from = columnOf(hop.table, hop.from);

        pairs.push({
          subject: type,
          where: `${where} through[${String(hopIndex)}]`,
          left: from,
          right: previous,
        });
        previous = columnOf(hop.table, hop.to);
      }
    }
  }

  return pairs;
}

/** `text` and `varchar` are one comparison type. */
export function searchKeyTypeKey(type: string): string {
  const flat = type.toLowerCase().replaceAll(/\s+/g, " ").trim();

  if (
    flat === "text" ||
    flat === "varchar" ||
    flat.startsWith("varchar(") ||
    flat === "character varying" ||
    flat.startsWith("character varying(")
  ) {
    return "text";
  }

  return flat;
}

const typeKey = (
  types: readonly SearchKeyType[],
  column: SearchKeyColumn,
): string | undefined => {
  const found = types.find(
    (entry) =>
      entry.schema === column.schema &&
      entry.table === column.table &&
      entry.column === column.column,
  );

  return found === undefined ? undefined : searchKeyTypeKey(found.type);
};

/**
 * Pairs whose catalog types differ. A column the catalog does not list is
 * skipped: the schema may not be applied yet.
 */
export function searchKeyMismatches(
  pairs: readonly SearchKeyPair[],
  types: readonly SearchKeyType[],
): readonly SearchKeyPair[] {
  return pairs.filter((pair) => {
    const left = typeKey(types, pair.left);
    const right = typeKey(types, pair.right);

    return left !== undefined && right !== undefined && left !== right;
  });
}

const quote = (name: string): string => `"${name.replaceAll('"', '""')}"`;

async function columnTypes(
  context: DoctorContext,
  pairs: readonly SearchKeyPair[],
): Promise<SearchKeyType[] | undefined> {
  const db = context.database;

  if (!db || "skipped" in db) {
    return undefined;
  }

  const tables = [
    ...new Set(
      pairs.flatMap((pair) => [
        `${pair.left.schema}.${pair.left.table}`,
        `${pair.right.schema}.${pair.right.table}`,
      ]),
    ),
  ];

  if (tables.length === 0) {
    return [];
  }

  const list = tables
    .map((table) => {
      const dot = table.indexOf(".");

      return `(${literal(table.slice(0, dot))}, ${literal(table.slice(dot + 1))})`;
    })
    .join(", ");

  return db.query<SearchKeyType>(
    `select n.nspname as schema, c.relname as table, a.attname as column, format_type(a.atttypid, a.atttypmod) as type
     from pg_attribute a
     join pg_class c on c.oid = a.attrelid
     join pg_namespace n on n.oid = c.relnamespace
     where a.attnum > 0 and not a.attisdropped
       and (n.nspname, c.relname) in (${list})`,
  );
}

export const SEARCH_KEY_RULES: readonly Rule[] = [
  {
    code: "BS632",
    severity: "warning",
    title: "A search key comparison mixes column types",
    description:
      "Search joins and watch lookups compare keys on their own type. When the live catalog gives the two columns different types, that comparison stays text and cannot use the key's index. Give the columns one type, or set the subject's idType to the type they share.",
    async check(context) {
      const pairs = searchKeyPairs(context.config.subjects);
      const types = await columnTypes(context, pairs);

      if (types === undefined) {
        return [];
      }

      return searchKeyMismatches(pairs, types).map((pair): FindingInput => ({
        message: `${quote(pair.left.schema)}.${quote(pair.left.table)}.${quote(pair.left.column)} and ${quote(pair.right.schema)}.${quote(pair.right.table)}.${quote(pair.right.column)} have different types, so ${pair.where} compares them as text.`,
        target: `${pair.left.schema}.${pair.left.table}.${pair.left.column}`,
        help: "Make the two columns the same type. Search can then compare them without a cast.",
      }));
    },
  },
];
