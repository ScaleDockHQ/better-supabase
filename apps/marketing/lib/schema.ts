import type { Preset } from "better-supabase/preset";

/** One rendered SQL file, as `/create/migrations` returns it. */
export interface SchemaSource {
  readonly path: string;
  readonly module: string;
  readonly contents: string;
}

/** The table a foreign key points at. `columns` is empty when the SQL names none: the target's primary key. */
export interface SchemaTarget {
  readonly schema: string;
  readonly table: string;
  readonly columns: readonly string[];
}

export interface SchemaForeignKey {
  readonly columns: readonly string[];
  readonly target: SchemaTarget;
  /** The `on delete` action, lower case: `cascade`, `set null`, `no action`. */
  readonly onDelete: string;
}

export interface SchemaColumn {
  readonly name: string;
  readonly type: string;
  readonly nullable: boolean;
  /** The default expression as the SQL writes it, or `null` without one. */
  readonly default: string | null;
  readonly unique: boolean;
  /** What the column is beyond its type (`email`, `select`), when it is more. */
  readonly label?: string;
}

export interface SchemaTable {
  /** `schema.name`, unquoted. */
  readonly id: string;
  readonly schema: string;
  readonly name: string;
  /** The module whose file creates the table. */
  readonly module: string;
  readonly primaryKey: readonly string[];
  readonly foreignKeys: readonly SchemaForeignKey[];
  readonly tenantColumn: string | null;
  /** Every column, in table order. */
  readonly columns: readonly SchemaColumn[];
  /** The rollups and lookups of an app table, which its `<table>_view` adds. */
  readonly computed?: readonly SchemaComputed[];
}

/** A column of an app table's view: a rollup or a lookup. */
export interface SchemaComputed {
  readonly name: string;
  readonly kind: "rollup" | "lookup";
  readonly summary: string;
  readonly label: string;
}

/**
 * A column that points at a table without a foreign key: the tenant or user
 * column a block keeps plain so its rows outlive deletes, or a `regclass`
 * that names any table (`to` is `null`).
 */
export interface SchemaSoftRef {
  readonly from: string;
  readonly column: string;
  readonly to: string | null;
  readonly kind: "tenant" | "user" | "any";
}

/** What `/create/schema` returns. */
export interface SchemaData {
  readonly tables: readonly SchemaTable[];
  readonly softRefs: readonly SchemaSoftRef[];
  /** Table id to the block manifest that installs it. */
  readonly manifests: Readonly<Record<string, string>>;
  /** The table ids `blocks.<module>.options.extraColumns` adds columns to. */
  readonly extraColumns: readonly string[];
  /** Table id to its module and logical table, the names an app table's reference uses. */
  readonly blockTables: Readonly<
    Record<string, { readonly block: string; readonly table: string }>
  >;
  /** The table tenant columns point at, or `null` without tenant foreign keys. */
  readonly tenantTable: string | null;
}

/** The columns a diagram shows before a table is expanded: keys, tenant and soft references. */
export function keyColumnsOf(
  table: SchemaTable,
  softColumns: ReadonlySet<string> = new Set(),
): readonly SchemaColumn[] {
  const keys = new Set([
    ...table.primaryKey,
    ...table.foreignKeys.flatMap((key) => key.columns),
    ...(table.tenantColumn === null ? [] : [table.tenantColumn]),
    ...softColumns,
  ]);

  return table.columns.filter((column) => keys.has(column.name));
}

export interface SchemaOptions {
  /** The tenant column the config names (`organization_id` by default); `null` without tenants. */
  readonly tenantColumn?: string | null;
}

/** The column the tenant blocks key rows by, from the preset's tenant name; `null` without tenants. */
export function tenantColumnOf(preset: Preset): string | null {
  return preset.scope === "tenant" ? `${preset.tenantName}_id` : null;
}

/**
 * Every module's file creates this table to record the installed modules.
 * It holds no app data, so the diagram leaves it out.
 */
const BOOKKEEPING_TABLES = new Set(["better_supabase.modules"]);

const IDENT = String.raw`(?:"(?:[^"]|"")+"|[A-Za-z_][A-Za-z0-9_$]*)`;
const QNAME = String.raw`${IDENT}(?:\s*\.\s*${IDENT})?`;

const CREATE_TABLE =
  /\bcreate\s+(?:(?:global\s+|local\s+)?(?:temp|temporary)\s+|unlogged\s+)?table\b/giu;

const CREATE_HEAD = new RegExp(
  String.raw`^create\s+(?:(?:global\s+|local\s+)?(?:temp|temporary)\s+|unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?(${QNAME})\s*\(`,
  "iu",
);

const ALTER_TABLE = new RegExp(
  String.raw`\balter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(${QNAME})\s+([^;]*);`,
  "giu",
);

const REFERENCES = new RegExp(
  String.raw`\breferences\s+(${QNAME})\s*(?:\(([^)]*)\))?`,
  "iu",
);

const LEADING_IDENT = new RegExp(String.raw`^(${IDENT})\s*`, "u");

const CONSTRAINT_NAME = new RegExp(String.raw`^constraint\s+${IDENT}\s+`, "iu");

/** Words that end a column's type in its definition. */
const TYPE_END =
  /\s+(?:not\b|null\b|primary\b|references\b|default\b|generated\b|unique\b|check\b|constraint\b|collate\b)/iu;

function unquote(ident: string): string {
  const trimmed = ident.trim();

  return trimmed.startsWith('"')
    ? trimmed.slice(1, -1).replaceAll('""', '"')
    : trimmed.toLowerCase();
}

function qualified(name: string): { schema: string; table: string } {
  const parts = name.match(new RegExp(IDENT, "gu")) ?? [];
  const [first = "", second] = parts.map((each) => unquote(each));

  return second === undefined
    ? { schema: "public", table: first }
    : { schema: first, table: second };
}

function identList(list: string | undefined): string[] {
  return (list ?? "")
    .split(",")
    .map((each) => each.trim())
    .filter((each) => each !== "")
    .map((each) => unquote(each));
}

/**
 * The SQL with comments removed and the inside of every single-quoted string
 * blanked, so a `create table` inside a string or a comment is not read and
 * the offsets still match the original text.
 */
function codeOnly(sql: string): string {
  let out = "";
  let index = 0;

  while (index < sql.length) {
    const char = sql[index];
    const next = sql[index + 1];

    if (char === "-" && next === "-") {
      const end = sql.indexOf("\n", index);
      const stop = end === -1 ? sql.length : end;
      out += " ".repeat(stop - index);
      index = stop;
    } else if (char === "/" && next === "*") {
      const end = sql.indexOf("*/", index + 2);
      const stop = end === -1 ? sql.length : end + 2;
      out += sql.slice(index, stop).replaceAll(/[^\n]/gu, " ");
      index = stop;
    } else if (char === "'") {
      let stop = index + 1;

      while (stop < sql.length) {
        if (sql[stop] === "'" && sql[stop + 1] === "'") {
          stop += 2;
        } else if (sql[stop] === "'") {
          break;
        } else {
          stop += 1;
        }
      }

      out += `'${sql.slice(index + 1, stop).replaceAll(/[^\n]/gu, " ")}'`;
      index = stop + 1;
    } else {
      out += char;
      index += 1;
    }
  }

  return out;
}

/** The text between the `(` at `open` and its matching `)`, or undefined when it never closes. */
function balanced(text: string, open: number): string | undefined {
  let depth = 0;

  for (let index = open; index < text.length; index += 1) {
    if (text[index] === "(") {
      depth += 1;
    } else if (text[index] === ")") {
      depth -= 1;

      if (depth === 0) {
        return text.slice(open + 1, index);
      }
    }
  }

  return undefined;
}

interface Element {
  /** The element with comments and string contents blanked. */
  readonly code: string;
  /** The same element as written. */
  readonly original: string;
}

/** The comma-separated elements of `text` at depth 0, with `original` sliced at the same offsets. */
function splitTopLevel(text: string, original: string = text): Element[] {
  const parts: Element[] = [];
  let depth = 0;
  let start = 0;

  const push = (end: number): void => {
    const code = text.slice(start, end);
    const lead = code.length - code.trimStart().length;
    const trimmed = code.trim();

    if (trimmed !== "") {
      parts.push({
        code: trimmed,
        original: original.slice(start + lead, start + lead + trimmed.length),
      });
    }
  };

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];

    if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
    } else if (char === "," && depth === 0) {
      push(index);
      start = index + 1;
    }
  }

  push(text.length);

  return parts;
}

function lineOf(text: string, offset: number): number {
  return text.slice(0, offset).split("\n").length;
}

interface TableDraft {
  readonly schema: string;
  readonly name: string;
  readonly module: string;
  readonly columns: SchemaColumn[];
  primaryKey: string[];
  readonly foreignKeys: SchemaForeignKey[];
}

function target(match: RegExpMatchArray): SchemaTarget {
  const { schema, table } = qualified(match[1] ?? "");

  return { schema, table, columns: identList(match[2]) };
}

const ON_DELETE =
  /\bon\s+delete\s+(cascade|restrict|set\s+null|set\s+default|no\s+action)\b/iu;

/** The `on delete` action of a reference, `no action` when it names none. */
function onDeleteOf(text: string): string {
  return (ON_DELETE.exec(text)?.[1] ?? "no action")
    .toLowerCase()
    .replaceAll(/\s+/gu, " ");
}

/** Words that end a column's default expression at the top level. */
const DEFAULT_END =
  /^(?:not\s+null|null|primary\s+key|references|unique|check|constraint|generated|collate)\b/iu;

/**
 * The `default` expression of a column definition. `definition` is the code
 * with strings blanked and `original` the same text as written, so a keyword
 * inside a string never ends the expression.
 */
function defaultOf(definition: string, original: string): string | null {
  const start = /\bdefault\s+/iu.exec(definition);

  if (start === null) {
    return null;
  }

  const from = start.index + start[0].length;
  let depth = 0;
  let end = definition.length;

  for (let index = from; index < definition.length; index += 1) {
    const char = definition[index];

    if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
    } else if (
      depth === 0 &&
      /\s/u.test(char ?? "") &&
      DEFAULT_END.test(definition.slice(index).trimStart())
    ) {
      end = index;
      break;
    }
  }

  return original.slice(from, end).trim();
}

/** Adds a column definition (`"name" type ...`) to the draft. */
function addColumn(
  draft: TableDraft,
  definition: string,
  original: string = definition,
): void {
  const head = definition.match(LEADING_IDENT);

  if (head === null) {
    return;
  }

  const name = unquote(head[1] ?? "");
  const rest = definition.slice(head[0].length);
  const typeEnd = rest.search(TYPE_END);
  const type = (typeEnd === -1 ? rest : rest.slice(0, typeEnd)).trim();

  if (draft.columns.some((column) => column.name === name)) {
    return;
  }

  const primary = /\bprimary\s+key\b/iu.test(rest);

  draft.columns.push({
    name,
    type,
    nullable: !primary && !/\bnot\s+null\b/iu.test(rest),
    default: defaultOf(definition, original),
    unique: /\bunique\b/iu.test(rest),
  });

  if (primary) {
    draft.primaryKey = [name];
  }

  const references = rest.match(REFERENCES);

  if (references !== null) {
    draft.foreignKeys.push({
      columns: [name],
      target: target(references),
      onDelete: onDeleteOf(rest),
    });
  }
}

/**
 * Adds a table constraint (`primary key (...)`, `foreign key (...)
 * references ...`). Returns false when the element is not a constraint.
 */
function addConstraint(draft: TableDraft, element: string): boolean {
  const body = element.replace(CONSTRAINT_NAME, "");
  const named = body !== element;

  const primary = /^primary\s+key\s*\(([^)]*)\)/iu.exec(body);

  if (primary !== null) {
    draft.primaryKey = identList(primary[1]);

    return true;
  }

  const foreign = /^foreign\s+key\s*\(([^)]*)\)\s*([\s\S]*)$/iu.exec(body);

  if (foreign !== null) {
    const references = (foreign[2] ?? "").match(REFERENCES);

    if (references !== null) {
      draft.foreignKeys.push({
        columns: identList(foreign[1]),
        target: target(references),
        onDelete: onDeleteOf(foreign[2] ?? ""),
      });
    }

    return true;
  }

  return named || /^(?:unique|check|exclude)\b/iu.test(body);
}

function finish(draft: TableDraft, tenantColumn: string | null): SchemaTable {
  const tenant =
    tenantColumn !== null &&
    draft.columns.some((column) => column.name === tenantColumn)
      ? tenantColumn
      : null;

  const primary = new Set(draft.primaryKey);

  return {
    id: `${draft.schema}.${draft.name}`,
    schema: draft.schema,
    name: draft.name,
    module: draft.module,
    primaryKey: draft.primaryKey,
    foreignKeys: draft.foreignKeys,
    tenantColumn: tenant,
    // A table-level `primary key (...)` makes its columns not null too.
    columns: draft.columns.map((column) =>
      primary.has(column.name) ? { ...column, nullable: false } : column,
    ),
  };
}

/**
 * The tables in rendered module SQL: every `create table`, plus the columns
 * and foreign keys later `alter table ... add` statements give them. A
 * `create table` it can't read throws with the file and line, so a new SQL
 * shape fails the tests instead of dropping a table from the diagram.
 */
export function parseSchema(
  files: readonly SchemaSource[],
  options: SchemaOptions = {},
): readonly SchemaTable[] {
  const drafts = new Map<string, TableDraft>();
  const code = files.map((file) => ({ file, text: codeOnly(file.contents) }));

  for (const { file, text } of code) {
    for (const match of text.matchAll(CREATE_TABLE)) {
      const offset = match.index;
      const head = text.slice(offset).match(CREATE_HEAD);
      const open = head === null ? -1 : offset + head[0].length - 1;
      const body = open === -1 ? undefined : balanced(text, open);

      const original =
        body === undefined
          ? ""
          : file.contents.slice(open + 1, open + 1 + body.length);

      if (head === null || body === undefined) {
        throw new Error(
          `parseSchema can't read the create table at ${file.path}:${lineOf(text, offset)}.`,
        );
      }

      const { schema, table } = qualified(head[1] ?? "");
      const id = `${schema}.${table}`;

      if (drafts.has(id)) {
        continue;
      }

      const draft: TableDraft = {
        schema,
        name: table,
        module: file.module,
        columns: [],
        primaryKey: [],
        foreignKeys: [],
      };

      for (const element of splitTopLevel(body, original)) {
        if (!addConstraint(draft, element.code)) {
          addColumn(draft, element.code, element.original);
        }
      }

      drafts.set(id, draft);
    }
  }

  for (const { file, text } of code) {
    for (const match of text.matchAll(ALTER_TABLE)) {
      const { schema, table } = qualified(match[1] ?? "");
      const draft = drafts.get(`${schema}.${table}`);

      if (draft === undefined) {
        continue;
      }

      const actions = match[2] ?? "";
      const start = match.index + match[0].lastIndexOf(actions);
      const original = file.contents.slice(start, start + actions.length);

      for (const action of splitTopLevel(actions, original)) {
        const column = /^add\s+column\s+(?:if\s+not\s+exists\s+)?/iu.exec(
          action.code,
        );

        if (column !== null) {
          addColumn(
            draft,
            action.code.slice(column[0].length),
            action.original.slice(column[0].length),
          );
        } else if (/^add\s+/iu.test(action.code)) {
          addConstraint(draft, action.code.replace(/^add\s+/iu, ""));
        }
      }
    }
  }

  const tenantColumn = options.tenantColumn ?? null;

  return [...drafts.entries()]
    .filter(([id]) => !BOOKKEEPING_TABLES.has(id))
    .map(([, draft]) => finish(draft, tenantColumn));
}

/**
 * The statements that shape one table, as written: its `create table` and
 * the `alter table` statements after it. Empty when no file creates it.
 */
export function tableStatements(
  files: readonly SchemaSource[],
  id: string,
): readonly string[] {
  const statements: string[] = [];

  for (const file of files) {
    const text = codeOnly(file.contents);

    for (const match of text.matchAll(CREATE_TABLE)) {
      const head = text.slice(match.index).match(CREATE_HEAD);

      if (head === null) {
        continue;
      }

      const { schema, table } = qualified(head[1] ?? "");
      const open = match.index + head[0].length - 1;
      const body = balanced(text, open);

      if (`${schema}.${table}` !== id || body === undefined) {
        continue;
      }

      const end = text.indexOf(";", open + body.length + 1);
      statements.push(
        file.contents.slice(match.index, end === -1 ? text.length : end + 1),
      );
    }

    for (const match of text.matchAll(ALTER_TABLE)) {
      const { schema, table } = qualified(match[1] ?? "");

      if (`${schema}.${table}` === id) {
        statements.push(
          file.contents.slice(match.index, match.index + match[0].length),
        );
      }
    }
  }

  return statements;
}

/** The foreign keys between tables, one per pair, with the targets outside the schema named by id. */
export function schemaRelations(
  tables: readonly SchemaTable[],
): readonly { readonly from: string; readonly to: string }[] {
  const seen = new Set<string>();

  return tables.flatMap((table) =>
    table.foreignKeys.flatMap((key) => {
      const to = `${key.target.schema}.${key.target.table}`;
      const pair = `${table.id}>${to}`;

      if (to === table.id || seen.has(pair)) {
        return [];
      }

      seen.add(pair);

      return [{ from: table.id, to }];
    }),
  );
}
