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
}

export interface SchemaColumn {
  readonly name: string;
  readonly type: string;
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
  /** The primary key, foreign key and tenant columns, in table order. */
  readonly keyColumns: readonly SchemaColumn[];
  readonly columnCount: number;
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

function splitTopLevel(text: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let start = 0;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];

    if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
    } else if (char === "," && depth === 0) {
      parts.push(text.slice(start, index));
      start = index + 1;
    }
  }

  parts.push(text.slice(start));

  return parts.map((each) => each.trim()).filter((each) => each !== "");
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

/** Adds a column definition (`"name" type ...`) to the draft. */
function addColumn(draft: TableDraft, definition: string): void {
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

  draft.columns.push({ name, type });

  if (/\bprimary\s+key\b/iu.test(rest)) {
    draft.primaryKey = [name];
  }

  const references = rest.match(REFERENCES);

  if (references !== null) {
    draft.foreignKeys.push({ columns: [name], target: target(references) });
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

  const keys = new Set([
    ...draft.primaryKey,
    ...draft.foreignKeys.flatMap((key) => key.columns),
    ...(tenant === null ? [] : [tenant]),
  ]);

  return {
    id: `${draft.schema}.${draft.name}`,
    schema: draft.schema,
    name: draft.name,
    module: draft.module,
    primaryKey: draft.primaryKey,
    foreignKeys: draft.foreignKeys,
    tenantColumn: tenant,
    keyColumns: draft.columns.filter((column) => keys.has(column.name)),
    columnCount: draft.columns.length,
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

      for (const element of splitTopLevel(body)) {
        if (!addConstraint(draft, element)) {
          addColumn(draft, element);
        }
      }

      drafts.set(id, draft);
    }
  }

  for (const { text } of code) {
    for (const match of text.matchAll(ALTER_TABLE)) {
      const { schema, table } = qualified(match[1] ?? "");
      const draft = drafts.get(`${schema}.${table}`);

      if (draft === undefined) {
        continue;
      }

      for (const action of splitTopLevel(match[2] ?? "")) {
        const column =
          /^add\s+column\s+(?:if\s+not\s+exists\s+)?([\s\S]+)$/iu.exec(action);

        if (column !== null) {
          addColumn(draft, column[1] ?? "");
        } else if (/^add\s+/iu.test(action)) {
          addConstraint(draft, action.replace(/^add\s+/iu, ""));
        }
      }
    }
  }

  const tenantColumn = options.tenantColumn ?? null;

  return [...drafts.entries()]
    .filter(([id]) => !BOOKKEEPING_TABLES.has(id))
    .map(([, draft]) => finish(draft, tenantColumn));
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
