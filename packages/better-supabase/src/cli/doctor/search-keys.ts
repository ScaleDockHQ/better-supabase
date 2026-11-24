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
function searchKeyTypeKey(type: string): string {
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

/** A source view of a record type, with the columns its config lists. */
export interface SearchViewSource {
  readonly subject: string;
  readonly view: SearchKeyColumn;
  readonly table: SearchKeyColumn;
  readonly columns: readonly string[];
}

/** One base-table column a view reads, from `view_column_usage`. */
export interface ViewColumnUse {
  readonly view_schema: string;
  readonly view_name: string;
  readonly table_schema: string;
  readonly table_name: string;
  readonly column_name: string;
}

/** The record types that read through `search.from`. */
export function searchViewSources(
  subjects: SubjectsConfig,
): SearchViewSource[] {
  return Object.entries(subjects).flatMap(([type, subject]) => {
    const from = subject.search?.from;

    return from === undefined
      ? []
      : [
          {
            subject: type,
            view: split(from.view),
            table: split(subject.table),
            // The trigger also watches the id, tenant, exclude and deletedAt
            // columns of the record's own table.
            columns: [
              ...(subject.search?.columns ?? []),
              ...(subject.search?.exclude === undefined
                ? []
                : [subject.search.exclude]),
              subject.id ?? "id",
              ...(subject.tenant === false
                ? []
                : [subject.tenant ?? "organization_id"]),
              ...(subject.deletedAt === undefined ? [] : [subject.deletedAt]),
            ],
          },
        ];
  });
}

/**
 * The columns of the record's own table that a source view reads and
 * `search.columns` leaves out. An update of one of them leaves the index
 * stale.
 */
export function unlistedViewColumns(
  sources: readonly SearchViewSource[],
  uses: readonly ViewColumnUse[],
): { readonly source: SearchViewSource; readonly missing: string[] }[] {
  return sources.flatMap((source) => {
    const missing = uses
      .filter(
        (use) =>
          use.view_schema === source.view.schema &&
          use.view_name === source.view.table &&
          use.table_schema === source.table.schema &&
          use.table_name === source.table.table &&
          !source.columns.includes(use.column_name),
      )
      .map((use) => use.column_name);

    return missing.length === 0
      ? []
      : [{ source, missing: [...new Set(missing)].toSorted() }];
  });
}

async function viewColumnUses(
  context: DoctorContext,
  sources: readonly SearchViewSource[],
): Promise<ViewColumnUse[] | undefined> {
  const db = context.database;

  if (!db || "skipped" in db || sources.length === 0) {
    return undefined;
  }

  const list = sources
    .map(
      (source) =>
        `(${literal(source.view.schema)}, ${literal(source.view.table)})`,
    )
    .join(", ");

  return db.query<ViewColumnUse>(
    `select view_schema::text, view_name::text, table_schema::text, table_name::text, column_name::text
     from information_schema.view_column_usage
     where (view_schema, view_name) in (${list})`,
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
  {
    code: "BS637",
    severity: "warning",
    title: "A search source view reads a column search.columns leaves out",
    description:
      "A record type with `search.from` re-indexes on an update of the columns `search.columns` lists, because the generator cannot see what the view reads. Doctor reads `information_schema.view_column_usage` and reports each column of the record's own table that the view reads and the list leaves out: an update of it leaves the search document stale. Add the column to `search.columns`.",
    async check(context) {
      const sources = searchViewSources(context.config.subjects);
      const uses = await viewColumnUses(context, sources);

      if (uses === undefined) {
        return [];
      }

      return unlistedViewColumns(sources, uses).map(
        ({ source, missing }): FindingInput => ({
          message: `${quote(source.view.schema)}.${quote(source.view.table)} reads ${missing.map((name) => `"${name}"`).join(", ")} of ${quote(source.table.schema)}.${quote(source.table.table)}, which ${source.subject} search.columns does not list, so an update of ${missing.length === 1 ? "it" : "them"} leaves the search document stale.`,
          target: `${source.subject}.search.columns`,
          help: `Add ${missing.map((name) => `"${name}"`).join(", ")} to search.columns of ${source.subject}.`,
        }),
      );
    },
  },
];
