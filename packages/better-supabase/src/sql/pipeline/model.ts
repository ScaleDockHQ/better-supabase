import { NAME, qualified, unquote } from "../schema-scan.ts";
import { sha256Hex } from "../sha256.ts";
import { splitStatements } from "./split.ts";

/** What a statement declares. */
export type DeclaredKind =
  | "table"
  | "view"
  | "function"
  | "index"
  | "policy"
  | "trigger"
  | "type"
  | "sequence"
  | "schema"
  | "extension";

/**
 * An object a file creates. `name` is `schema.name` (policies and triggers:
 * `schema.table.name`).
 */
export interface DeclaredObject {
  readonly kind: DeclaredKind;
  readonly name: string;
  readonly line: number;
  /** Written as `create ... if not exists`. */
  readonly ifNotExists: boolean;
}

/** Columns an `alter table` adds to a table the file may not create. */
export interface AlteredTable {
  readonly table: string;
  readonly columns: readonly string[];
  /** The columns with the type text after the name, in `columns` order. */
  readonly definitions: readonly {
    readonly name: string;
    readonly type: string;
  }[];
  readonly line: number;
}

/** The columns a `create table` statement declares, with their type text. */
export interface CreatedTable {
  readonly table: string;
  readonly definitions: readonly {
    readonly name: string;
    readonly type: string;
  }[];
}

/** What one file declares, before it is placed in the model. */
export interface ParsedFile {
  readonly objects: readonly DeclaredObject[];
  readonly alters: readonly AlteredTable[];
  /** Each `create table`, with its columns. */
  readonly creates: readonly CreatedTable[];
  /** `comment on table` targets with the text of their `@bsb` tag lines. */
  readonly tags: readonly { readonly table: string; readonly tags: string }[];
  /**
   * Each `create policy` with its table and everything after the table name,
   * lowercased with its whitespace collapsed, so two policies that decide the
   * same way have the same `terms`.
   */
  readonly policies: readonly {
    readonly table: string;
    readonly name: string;
    readonly terms: string;
    readonly line: number;
  }[];
  /** Lines of `do` blocks that create objects at run time. */
  readonly doBlocks: readonly number[];
  /** Lines of top-level `insert` statements. */
  readonly inserts: readonly number[];
  /** The file asks pg-delta for `transaction=false`. */
  readonly outsideTransaction: boolean;
}

/**
 * Changes whenever `parseDeclared` learns a new statement, so a cache drops old
 * entries.
 */
const PARSER_VERSION = 4;

const IDENT = String.raw`${NAME}(?:\s*\.\s*${NAME})?`;

const rule = (source: string): RegExp => new RegExp(`^${source}`, "i");

const CREATE: readonly {
  readonly kind: DeclaredKind;
  readonly pattern: RegExp;
}[] = [
  {
    kind: "table",
    pattern: rule(
      String.raw`create\s+(?:unlogged\s+|temporary\s+|temp\s+)?table\s+(if\s+not\s+exists\s+)?(${IDENT})`,
    ),
  },
  {
    kind: "view",
    pattern: rule(
      String.raw`create\s+(?:or\s+replace\s+)?(?:materialized\s+|recursive\s+|temporary\s+)?view\s+(if\s+not\s+exists\s+)?(${IDENT})`,
    ),
  },
  {
    kind: "function",
    pattern: rule(
      String.raw`create\s+(?:or\s+replace\s+)?(?:function|procedure)\s+(?:(if\s+not\s+exists)\s+)?(${IDENT})\s*\(`,
    ),
  },
  {
    kind: "type",
    pattern: rule(
      String.raw`create\s+(?:type|domain)\s+(?:(if\s+not\s+exists)\s+)?(${IDENT})`,
    ),
  },
  {
    kind: "sequence",
    pattern: rule(
      String.raw`create\s+(?:temporary\s+|temp\s+|unlogged\s+)?sequence\s+(if\s+not\s+exists\s+)?(${IDENT})`,
    ),
  },
  {
    kind: "schema",
    pattern: rule(
      String.raw`create\s+schema\s+(if\s+not\s+exists\s+)?(${NAME})`,
    ),
  },
  {
    kind: "extension",
    pattern: rule(
      String.raw`create\s+extension\s+(if\s+not\s+exists\s+)?(${NAME})`,
    ),
  },
];

const INDEX = rule(
  String.raw`create\s+(?:unique\s+)?index\s+(?:concurrently\s+)?(if\s+not\s+exists\s+)?(${NAME})\s+on\s+(?:only\s+)?(${IDENT})`,
);

const POLICY = rule(String.raw`create\s+policy\s+(${NAME})\s+on\s+(${IDENT})`);

const TRIGGER = new RegExp(
  String.raw`^create\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+(${NAME})\b[\s\S]*?\bon\s+(${IDENT})`,
  "i",
);

const ALTER = rule(
  String.raw`alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(${IDENT})\s+([\s\S]*)`,
);

const ADD_COLUMN = new RegExp(
  String.raw`^add\s+column\s+(?:if\s+not\s+exists\s+)?(${NAME})\s*([\s\S]*)$`,
  "i",
);

/** `body` split at the commas outside parentheses and quotes. */
function topLevelParts(body: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let quote: string | undefined;
  let start = 0;

  for (let at = 0; at < body.length; at += 1) {
    const char = body[at]!;

    if (quote !== undefined) {
      if (char === quote) {
        quote = undefined;
      }
    } else if (char === "'" || char === '"') {
      quote = char;
    } else if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
    } else if (char === "," && depth === 0) {
      parts.push(body.slice(start, at).trim());
      start = at + 1;
    }
  }

  parts.push(body.slice(start).trim());

  return parts;
}

const COLUMN_DEFINITION = new RegExp(
  String.raw`^(?!(?:constraint|primary|unique|foreign|check|exclude|like)\b)(${NAME})\s+([\s\S]+)$`,
  "i",
);

/** The columns of a `create table` statement written as `flat`. */
function createdColumns(
  flat: string,
  from: number,
): readonly { readonly name: string; readonly type: string }[] {
  const open = flat.indexOf("(", from);

  if (open === -1) {
    return [];
  }

  let depth = 0;
  let quote: string | undefined;
  let close = flat.length;

  for (let at = open; at < flat.length; at += 1) {
    const char = flat[at]!;

    if (quote !== undefined) {
      quote = char === quote ? undefined : quote;
    } else if (char === "'" || char === '"') {
      quote = char;
    } else if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;

      if (depth === 0) {
        close = at;
        break;
      }
    }
  }

  return topLevelParts(flat.slice(open + 1, close)).flatMap((part) => {
    const column = COLUMN_DEFINITION.exec(part);

    return column === null
      ? []
      : [{ name: unquote(column[1]!), type: column[2]!.trim() }];
  });
}

const COMMENT_TABLE = rule(
  String.raw`comment\s+on\s+table\s+(${IDENT})\s+is\s+'((?:[^']|'')*)'`,
);

const DO_CREATES =
  /\bcreate\s+(?:or\s+replace\s+)?(?:unique\s+)?(?:table|index|view|function|trigger|policy|type|schema)\b|\bexecute\b/i;

const OUTSIDE_TRANSACTION = /^--\s*pg-delta:\s*transaction\s*=\s*false\b/im;

/** The schema-qualified, unquoted name of `target`. */
const nameOf = (target: string): string => qualified(target);

/** The argument count of a function, so overloads stay apart. */
function arity(statement: string, open: number): number {
  let depth = 0;
  let count = 0;
  let any = false;

  for (let at = open; at < statement.length; at += 1) {
    const char = statement[at];

    if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;

      if (depth === 0) {
        break;
      }
    } else if (depth === 1 && char === ",") {
      count += 1;
    } else if (depth === 1 && !/\s/.test(char ?? "")) {
      any = true;
    }
  }

  return any ? count + 1 : 0;
}

/** What `text` declares. Pure: the same text gives the same result. */
export function parseDeclared(text: string): ParsedFile {
  const objects: DeclaredObject[] = [];
  const alters: AlteredTable[] = [];
  const creates: CreatedTable[] = [];
  const tags: { table: string; tags: string }[] = [];
  const doBlocks: number[] = [];
  const inserts: number[] = [];

  const policies: {
    table: string;
    name: string;
    terms: string;
    line: number;
  }[] = [];

  for (const statement of splitStatements(text)) {
    const flat = statement.text.replaceAll(/\s+/g, " ");
    const line = statement.line;

    if (/^do\b/i.test(flat)) {
      if (DO_CREATES.test(flat)) {
        doBlocks.push(line);
      }

      continue;
    }

    if (/^insert\s+into\b/i.test(flat)) {
      inserts.push(line);
      continue;
    }

    const index = INDEX.exec(flat);

    if (index) {
      const table = nameOf(index[3]!);
      const schema = table.slice(0, table.indexOf("."));

      objects.push({
        kind: "index",
        name: `${schema}.${unquote(index[2]!)}`,
        line,
        ifNotExists: index[1] !== undefined,
      });
      continue;
    }

    const policy = POLICY.exec(flat);

    if (policy) {
      policies.push({
        table: nameOf(policy[2]!),
        name: unquote(policy[1]!),
        terms: flat.slice(policy[0].length).trim().toLowerCase(),
        line,
      });
      objects.push({
        kind: "policy",
        name: `${nameOf(policy[2]!)}.${unquote(policy[1]!)}`,
        line,
        ifNotExists: false,
      });
      continue;
    }

    const trigger = TRIGGER.exec(flat);

    if (trigger) {
      objects.push({
        kind: "trigger",
        name: `${nameOf(trigger[2]!)}.${unquote(trigger[1]!)}`,
        line,
        ifNotExists: false,
      });
      continue;
    }

    const created = CREATE.flatMap((entry) => {
      const match = entry.pattern.exec(flat);

      return match ? [{ entry, match }] : [];
    })[0];

    if (created) {
      const target = created.match[2]!;

      const name =
        created.entry.kind === "schema" || created.entry.kind === "extension"
          ? unquote(target)
          : nameOf(target);

      const open =
        created.entry.kind === "function"
          ? flat.indexOf("(", created.match[0].length - 1)
          : -1;

      if (created.entry.kind === "table") {
        creates.push({
          table: name,
          definitions: createdColumns(flat, created.match[0].length),
        });
      }

      objects.push({
        kind: created.entry.kind,
        name: open === -1 ? name : `${name}/${String(arity(flat, open))}`,
        line,
        ifNotExists: created.match[1] !== undefined,
      });
      continue;
    }

    const alter = ALTER.exec(flat);

    if (alter) {
      const definitions = topLevelParts(alter[2]!).flatMap((part) => {
        const column = ADD_COLUMN.exec(part);

        return column === null
          ? []
          : [{ name: unquote(column[1]!), type: column[2]!.trim() }];
      });

      if (definitions.length > 0) {
        alters.push({
          table: nameOf(alter[1]!),
          columns: definitions.map((definition) => definition.name),
          definitions,
          line,
        });
      }

      continue;
    }

    // The statement text, not `flat`: a tag reader needs the comment's line breaks.
    const comment = COMMENT_TABLE.exec(statement.text);

    if (comment) {
      tags.push({
        table: nameOf(comment[1]!),
        tags: comment[2]!.replaceAll("''", "'"),
      });
    }
  }

  return {
    objects,
    alters,
    creates,
    tags,
    policies,
    doBlocks,
    inserts,
    outsideTransaction: OUTSIDE_TRANSACTION.test(text),
  };
}

/**
 * A parse cache: the result of `parseDeclared` by content hash and parser
 * version.
 */
export interface ParseCache {
  readonly get: (text: string) => ParsedFile;
  /** How many texts were parsed and how many were found. */
  readonly stats: { parsed: number; hits: number };
}

/**
 * Where parse results live between runs. The CLI installs one that reads and
 * writes a file, so `src/sql` stays free of Node built-ins.
 */
export interface ParseStore {
  readonly get: (key: string) => unknown;
  readonly set: (key: string, value: ParsedFile) => void;
}

const STORE_KEY: unique symbol = Symbol.for("better-supabase.parse-store");

// The bundle can hold this module twice (the `./sql` entry and the CLI chunks),
// so the store lives on `globalThis`, where both copies find the same one.
// SAFETY: only this module writes STORE_KEY on globalThis, and it writes a ParseStore or undefined.
const shared = globalThis as { [STORE_KEY]?: ParseStore };

/** Installs the store new parse caches read and write, or removes it. */
export function setParseStore(store: ParseStore | undefined): void {
  if (store === undefined) {
    delete shared[STORE_KEY];
  } else {
    shared[STORE_KEY] = store;
  }
}

function isParsedFile(value: unknown): value is ParsedFile {
  return (
    typeof value === "object" &&
    value !== null &&
    "objects" in value &&
    Array.isArray(value.objects) &&
    "alters" in value &&
    Array.isArray(value.alters) &&
    "creates" in value &&
    Array.isArray(value.creates) &&
    "tags" in value &&
    Array.isArray(value.tags) &&
    "policies" in value &&
    Array.isArray(value.policies) &&
    "doBlocks" in value &&
    Array.isArray(value.doBlocks) &&
    "inserts" in value &&
    Array.isArray(value.inserts) &&
    "outsideTransaction" in value &&
    typeof value.outsideTransaction === "boolean"
  );
}

/**
 * A parse cache in memory, behind the installed store when there is one. Each
 * text is parsed once per content hash, and a text an earlier run parsed is
 * read from the store.
 */
export function createParseCache(
  store: ParseStore | undefined = shared[STORE_KEY],
): ParseCache {
  const entries = new Map<string, ParsedFile>();
  const stats = { parsed: 0, hits: 0 };

  return {
    stats,
    get(text) {
      const key = `${String(PARSER_VERSION)}:${sha256Hex(text)}`;
      const held = entries.get(key);

      if (held !== undefined) {
        stats.hits += 1;

        return held;
      }

      const stored = store?.get(key);

      if (isParsedFile(stored)) {
        stats.hits += 1;
        entries.set(key, stored);

        return stored;
      }

      stats.parsed += 1;
      const parsed = parseDeclared(text);
      entries.set(key, parsed);
      store?.set(key, parsed);

      return parsed;
    },
  };
}

/** Who owns a declaration: a module's file or one of the app's files. */
export type Owner =
  | { readonly kind: "module"; readonly name: string }
  | { readonly kind: "app"; readonly file: string };

const BLOCK_MARKER =
  /^-- @(?:bsb-block|bs-module)(?:-data)? ([a-zA-Z0-9-]+)(?:@\d+)?\b/m;

/** The owner of a file: the module its `@bsb-block` line names, else the app. */
export function ownerOf(path: string, text: string): Owner {
  const module = BLOCK_MARKER.exec(text)?.[1];

  return module === undefined
    ? { kind: "app", file: path }
    : { kind: "module", name: module };
}

/** One declaration in the model. */
export interface Declaration extends DeclaredObject {
  readonly owner: Owner;
  readonly file: string;
}

/** Every declared object of a set of schema files, with its owner. */
export interface SchemaModel {
  readonly files: ReadonlyMap<string, ParsedFile>;
  /** Declarations by `kind:name`. */
  readonly objects: ReadonlyMap<string, readonly Declaration[]>;
  /** Columns each owner adds to a table, by table. */
  readonly alters: ReadonlyMap<
    string,
    readonly { readonly owner: Owner; readonly columns: readonly string[] }[]
  >;
}

/** The column names a table comment's `@bsb fields a, b` line lists. */
function fieldsTagged(tags: string): readonly string[] {
  // The list ends at the end of its line or at the next `@bsb`.
  const line = /(?:^|\s)@bsb[ \t]+fields[ \t]+([^\n]+)/m.exec(tags)?.[1];

  return line === undefined
    ? []
    : (line.split(/\s@bsb\b/)[0] ?? "")
        .split(/[\s,]+/)
        .filter((name) => name !== "");
}

/**
 * A column the database fills (`generated always as`, `generated by default as
 * identity`): a block's functions can't write it, so it is never a field.
 */
const COMPUTED_COLUMN = /\bgenerated\s+(?:always|by\s+default)\s+as\b/i;

/**
 * The columns the app's own files make fields of a block's table, by
 * `schema.table`, with each column's type text: the ones an `alter table ...
 * add column` adds, and the ones a table comment lists as `@bsb fields a, b`
 * for a table the app creates.
 */
export function appColumnsOf(
  files: readonly { readonly path: string; readonly text: string }[],
  cache: ParseCache = createParseCache(),
): Readonly<
  Record<string, readonly { readonly name: string; readonly type: string }[]>
> {
  const columns: Record<string, { name: string; type: string }[]> = {};
  const created = new Map<string, Map<string, string>>();
  const tagged: { table: string; names: readonly string[] }[] = [];

  for (const file of files) {
    if (ownerOf(file.path, file.text).kind !== "app") {
      continue;
    }

    const parsed = cache.get(file.text);

    for (const table of parsed.creates) {
      const held = created.get(table.table) ?? new Map<string, string>();
      created.set(table.table, held);

      for (const definition of table.definitions) {
        held.set(definition.name, definition.type);
      }
    }

    for (const comment of parsed.tags) {
      const names = fieldsTagged(comment.tags);

      if (names.length > 0) {
        tagged.push({ table: comment.table, names });
      }
    }

    for (const alter of parsed.alters) {
      const list = columns[alter.table] ?? [];
      columns[alter.table] = list;

      for (const definition of alter.definitions) {
        if (
          !COMPUTED_COLUMN.test(definition.type) &&
          !list.some((held) => held.name === definition.name)
        ) {
          list.push(definition);
        }
      }
    }
  }

  for (const { table, names } of tagged) {
    const list = columns[table] ?? [];
    columns[table] = list;

    for (const name of names) {
      const type = created.get(table)?.get(name);

      if (
        type !== undefined &&
        !COMPUTED_COLUMN.test(type) &&
        !list.some((held) => held.name === name)
      ) {
        list.push({ name, type });
      }
    }
  }

  return columns;
}

/** The key of an object in the model. */
export const objectKey = (kind: DeclaredKind, name: string): string =>
  `${kind}:${name}`;

/** Builds the model from `files`, parsing each file through `cache`. */
export function buildModel(
  files: readonly { readonly path: string; readonly text: string }[],
  cache: ParseCache = createParseCache(),
): SchemaModel {
  const parsed = new Map<string, ParsedFile>();
  const objects = new Map<string, Declaration[]>();

  const alters = new Map<
    string,
    { owner: Owner; columns: readonly string[] }[]
  >();

  for (const file of files) {
    const result = cache.get(file.text);
    const owner = ownerOf(file.path, file.text);
    parsed.set(file.path, result);

    for (const object of result.objects) {
      const key = objectKey(object.kind, object.name);
      const list = objects.get(key) ?? [];
      list.push({ ...object, owner, file: file.path });
      objects.set(key, list);
    }

    for (const alter of result.alters) {
      const list = alters.get(alter.table) ?? [];
      list.push({ owner, columns: alter.columns });
      alters.set(alter.table, list);
    }
  }

  return { files: parsed, objects, alters };
}

/**
 * Policies on one table that decide the same way (command, roles, expressions)
 * under different names, with the file and line of each.
 */
export function duplicatePolicies(
  model: SchemaModel,
): readonly {
  readonly table: string;
  readonly names: readonly string[];
  readonly files: readonly { readonly file: string; readonly line: number }[];
}[] {
  const groups = new Map<
    string,
    { table: string; name: string; file: string; line: number }[]
  >();

  for (const [file, parsed] of model.files) {
    for (const policy of parsed.policies) {
      const key = `${policy.table}\0${policy.terms}`;
      const list = groups.get(key) ?? [];
      list.push({ ...policy, file });
      groups.set(key, list);
    }
  }

  return [...groups.values()]
    .filter(
      (list) =>
        list.length > 1 && new Set(list.map((each) => each.name)).size > 1,
    )
    .map((list) => ({
      table: list[0]!.table,
      names: [...new Set(list.map((each) => each.name))],
      files: list.map(({ file, line }) => ({ file, line })),
    }))
    .toSorted((a, b) => a.table.localeCompare(b.table));
}

const sameOwner = (a: Owner, b: Owner): boolean =>
  a.kind === "module"
    ? b.kind === "module" && a.name === b.name
    : b.kind === "app" && a.file === b.file;

/**
 * Objects declared by more than one owner (two modules, a module and an app
 * file, or two app files). `create or replace` of one function in two files of
 * the same owner is not a conflict.
 */
export function conflicts(
  model: SchemaModel,
): readonly {
  readonly key: string;
  readonly declarations: readonly Declaration[];
}[] {
  return [...model.objects.entries()]
    .filter(([, declarations]) =>
      declarations.some(
        (each) => !sameOwner(each.owner, declarations[0]!.owner),
      ),
    )
    .map(([key, declarations]) => ({ key, declarations }))
    .toSorted((a, b) => a.key.localeCompare(b.key));
}
