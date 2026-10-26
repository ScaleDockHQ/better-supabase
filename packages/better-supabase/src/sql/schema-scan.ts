import { withoutComments } from "./audit-registrations.ts";

/** Privileges one role gets on a table, from the policies that name it. */
export interface PolicyGrant {
  /** `schema.table`, unquoted; an unqualified name is in `public`. */
  readonly table: string;
  readonly role: "anon" | "authenticated";
  readonly privileges: readonly ("select" | "insert" | "update" | "delete")[];
}

export const NAME: string = String.raw`(?:"(?:[^"]|"")+"|[A-Za-z_][\w$]*)`;

const POLICY = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+policy\s+(${NAME})\s+on\s+(${NAME}(?:\s*\.\s*${NAME})?)((?:(?!\bcreate\s+policy\b)[\s\S])*?)(?:\busing\b|\bwith\s+check\b|;)`,
  "gi",
);

const DROP_POLICY = /* @__PURE__ */ new RegExp(
  String.raw`\bdrop\s+policy\s+(?:if\s+exists\s+)?(${NAME})\s+on\s+(${NAME}(?:\s*\.\s*${NAME})?)`,
  "gi",
);

const TABLE_NAME = String.raw`${NAME}(?:\s*\.\s*${NAME})?`;

const DROP_TABLE = /* @__PURE__ */ new RegExp(
  String.raw`\bdrop\s+table\s+(?:if\s+exists\s+)?(${TABLE_NAME}(?:\s*,\s*${TABLE_NAME})*)`,
  "gi",
);

function droppedTables(list: string): string[] {
  return (list.match(new RegExp(TABLE_NAME, "g")) ?? []).map(qualified);
}

type Statement = { readonly index: number; readonly apply: () => void };

function inOrder(statements: Statement[][]): void {
  for (const statement of statements
    .flat()
    .toSorted((a, b) => a.index - b.index)) {
    statement.apply();
  }
}

const COMMANDS = ["select", "insert", "update", "delete"] as const;

export const unquote = (name: string): string =>
  name.startsWith('"')
    ? name.slice(1, -1).replaceAll('""', '"')
    : name.toLowerCase();

export function qualified(target: string): string {
  const parts = (target.match(new RegExp(NAME, "g")) ?? []).map(unquote);

  return parts.length === 1 ? `public.${parts[0]!}` : parts.join(".");
}

export const TABLE: RegExp = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+(?:unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?(${NAME}(?:\s*\.\s*${NAME})?)\s*\(`,
  "gi",
);

/** `*` in a `schema.table` glob matches any run of characters. */
export function tableGlobs(globs: readonly string[]): RegExp[] {
  return globs.map(
    (glob) =>
      new RegExp(
        `^${glob
          .split("*")
          .map((part) => part.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&"))
          .join(".*")}$`,
        "i",
      ),
  );
}

/**
 * The tables `files` create (`create table`), as `schema.table`, in the order
 * they first appear. Only tables in `schemas` are kept.
 */
export function declaredTables(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): string[] {
  const found = new Set<string>();

  for (const file of files) {
    const text = withoutComments(file.text);
    inOrder([
      [...text.matchAll(TABLE)].map((match) => ({
        index: match.index,
        apply: () => {
          const table = qualified(match[1]!);

          if (schemas.includes(table.slice(0, table.indexOf(".")))) {
            found.add(table);
          }
        },
      })),
      [...text.matchAll(DROP_TABLE)].map((match) => ({
        index: match.index,
        apply: () => {
          for (const table of droppedTables(match[1]!)) {
            found.delete(table);
          }
        },
      })),
    ]);
  }

  return [...found];
}

/** A view the app's files create. */
export interface DeclaredView {
  /** Its columns, or `undefined` when they can't be read (`select *`). */
  readonly columns: readonly string[] | undefined;
  /** Whether `insert`, `update` and `delete` reach the table under it. */
  readonly updatable: boolean;
}

const VIEW = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+(?:or\s+replace\s+)?(?:(?:temp|temporary|recursive)\s+)?(materialized\s+)?view\s+(?:if\s+not\s+exists\s+)?(${TABLE_NAME})\s*(\()?`,
  "gi",
);

const DROP_VIEW = /* @__PURE__ */ new RegExp(
  String.raw`\bdrop\s+(?:materialized\s+)?view\s+(?:if\s+exists\s+)?(${TABLE_NAME}(?:\s*,\s*${TABLE_NAME})*)`,
  "gi",
);

const INSTEAD_OF_TRIGGER = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+(?:or\s+replace\s+)?trigger\s+${NAME}\s+instead\s+of\b[^;]*?\bon\s+(${TABLE_NAME})`,
  "gi",
);

/**
 * What keeps Postgres from writing through a view to its table: a view that has
 * one of these is not auto-updatable.
 */
const NOT_UPDATABLE =
  /\b(?:(?:distinct|group\s+by|having|limit|offset|fetch\s+first|union|intersect|except|join|window)\b|over\s*\(|(?:count|sum|avg|min|max|array_agg|string_agg|jsonb_agg|json_agg|bool_and|bool_or)\s*\()/i;

/** The word that ends a view's select list, at the top level. */
const SELECT_END = /\bfrom\b/i;

const ALIAS = /* @__PURE__ */ new RegExp(String.raw`\bas\s+(${NAME})\s*$`, "i");

const BARE_COLUMN = /* @__PURE__ */ new RegExp(
  String.raw`^(?:${NAME}\s*\.\s*)*(${NAME})$`,
);

/**
 * The view's columns from its select list: each item's alias, or the column it
 * names. `undefined` when an item is `*` or has no name to read.
 */
function selectColumns(body: string): string[] | undefined {
  const select = /^\s*(?:\(\s*)?select\s+/i.exec(body);

  if (select === null) {
    return undefined;
  }

  let rest = body.slice(select[0].length);
  const distinct = /^distinct\s+on\s*\(/i.exec(rest);

  if (distinct === null) {
    rest = rest.replace(/^(?:distinct|all)\b/i, "");
  } else {
    const close = closingParen(rest, distinct[0].length - 1);

    if (close === -1) {
      return undefined;
    }

    rest = rest.slice(close + 1);
  }

  const end = topLevelIndex(rest, SELECT_END);
  const items = splitTopLevel(end === -1 ? rest : rest.slice(0, end));
  const columns: string[] = [];

  for (const item of items) {
    const alias = ALIAS.exec(item)?.[1] ?? BARE_COLUMN.exec(item.trim())?.[1];

    if (alias === undefined || item.trim().endsWith("*")) {
      return undefined;
    }

    columns.push(unquote(alias));
  }

  return columns;
}

/** The first match of `pattern` outside parentheses and quotes, or -1. */
function topLevelIndex(text: string, pattern: RegExp): number {
  let depth = 0;
  let quote: string | undefined;

  for (let i = 0; i < text.length; i += 1) {
    const char = text[i]!;

    if (quote) {
      if (char === quote) {
        quote = undefined;
      }
    } else if (char === "'" || char === '"') {
      quote = char;
    } else if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
    } else if (
      depth === 0 &&
      /\w/.test(char) &&
      !/\w/.test(text[i - 1] ?? "") &&
      pattern.exec(text.slice(i))?.index === 0
    ) {
      return i;
    }
  }

  return -1;
}

/**
 * The views and materialized views `files` create, as `schema.view`, with their
 * columns and whether they are auto-updatable. A later `drop view` removes one.
 * Only views in `schemas` are kept.
 */
export function declaredViews(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): ReadonlyMap<string, DeclaredView> {
  const found = new Map<string, DeclaredView>();
  const insteadOf = new Set<string>();

  for (const file of files) {
    const text = withoutComments(file.text);

    for (const match of text.matchAll(INSTEAD_OF_TRIGGER)) {
      insteadOf.add(qualified(match[1]!));
    }

    inOrder([
      [...text.matchAll(VIEW)].map((match) => ({
        index: match.index,
        apply: () => {
          const view = qualified(match[2]!);

          if (!schemas.includes(view.slice(0, view.indexOf(".")))) {
            return;
          }

          let at = match.index + match[0].length;
          let listed: string[] | undefined;

          if (match[3] !== undefined) {
            const close = closingParen(text, at - 1);

            if (close === -1) {
              return;
            }

            listed = splitTopLevel(text.slice(at, close)).map((column) =>
              unquote(column.trim()),
            );
            at = close + 1;
          }

          const as = /\bas\b/i.exec(text.slice(at));

          if (as === null) {
            return;
          }

          const start = at + as.index + as[0].length;
          const end = text.indexOf(";", start);
          const body = text.slice(start, end === -1 ? text.length : end);

          found.set(view, {
            columns: listed ?? selectColumns(body),
            updatable: match[1] === undefined && !NOT_UPDATABLE.test(body),
          });
        },
      })),
      [...text.matchAll(DROP_VIEW)].map((match) => ({
        index: match.index,
        apply: () => {
          for (const view of droppedTables(match[1]!)) {
            found.delete(view);
          }
        },
      })),
    ]);
  }

  for (const view of insteadOf) {
    const entry = found.get(view);

    if (entry !== undefined) {
      found.set(view, { ...entry, updatable: true });
    }
  }

  return found;
}

const RLS_TOGGLE = /* @__PURE__ */ new RegExp(
  String.raw`\balter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(${NAME}(?:\s*\.\s*${NAME})?)\s+(enable|disable)\s+row\s+level\s+security\b`,
  "gi",
);

/**
 * The tables in `schemas` that `files` leave with row level security on: `alter
 * table ... enable row level security`, until a later `disable` or `drop
 * table`.
 */
export function rlsTables(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): string[] {
  const found = new Set<string>();

  for (const file of files) {
    const text = withoutComments(file.text);
    inOrder([
      [...text.matchAll(RLS_TOGGLE)].map((match) => ({
        index: match.index,
        apply: () => {
          const table = qualified(match[1]!);

          if (!schemas.includes(table.slice(0, table.indexOf(".")))) {
            return;
          }

          if (match[2]!.toLowerCase() === "enable") {
            found.add(table);
          } else {
            found.delete(table);
          }
        },
      })),
      [...text.matchAll(DROP_TABLE)].map((match) => ({
        index: match.index,
        apply: () => {
          for (const table of droppedTables(match[1]!)) {
            found.delete(table);
          }
        },
      })),
    ]);
  }

  return [...found];
}

const TABLE_CONSTRAINT =
  /^(constraint|check|unique|primary|foreign|exclude|like)\b/i;

/**
 * Columns each `create table` in `files` declares, as `schema.table` to
 * unquoted names. `like` and table constraints are skipped. Only tables in
 * `schemas` are kept.
 */
export function declaredTableColumns(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): ReadonlyMap<string, ReadonlySet<string>> {
  return new Map(
    [...declaredColumnTypes(files, schemas)].map(([table, columns]) => [
      table,
      new Set(columns.keys()),
    ]),
  );
}

const COLUMN_OPTION =
  /\s+(?:not\s+null|null|default|constraint|check|unique|primary\s+key|references|generated|collate)\b/i;

/**
 * The declared type of each column of each `create table` in `files`, as
 * `schema.table` to unquoted column name to type. A type is lower-cased with
 * its spacing normalised, and a quoted part keeps its case without quotes. Only
 * tables in `schemas` are kept.
 */
export function declaredColumnTypes(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): ReadonlyMap<string, ReadonlyMap<string, string>> {
  const found = new Map<string, Map<string, string>>();

  for (const file of files) {
    const text = withoutComments(file.text);

    for (const match of text.matchAll(TABLE)) {
      const table = qualified(match[1]!);

      if (!schemas.includes(table.slice(0, table.indexOf(".")))) {
        continue;
      }

      const open = match.index + match[0].length - 1;
      const close = closingParen(text, open);

      if (close === -1) {
        continue;
      }

      const columns = found.get(table) ?? new Map<string, string>();

      for (const part of splitTopLevel(text.slice(open + 1, close))) {
        const definition = part.trim();
        const first = new RegExp(`^${NAME}`).exec(definition)?.[0];

        if (first === undefined || TABLE_CONSTRAINT.test(definition)) {
          continue;
        }

        const rest = definition.slice(first.length);
        const option = COLUMN_OPTION.exec(rest);

        columns.set(
          unquote(first),
          typeName(option === null ? rest : rest.slice(0, option.index)),
        );
      }

      found.set(table, columns);
    }
  }

  return found;
}

function typeName(text: string): string {
  return text
    .trim()
    .replaceAll(/\s+/g, " ")
    .replaceAll(new RegExp(NAME, "g"), (part) => unquote(part));
}

const ENUM = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+type\s+(${NAME}(?:\s*\.\s*${NAME})?)\s+as\s+enum\b`,
  "gi",
);

/** The enum types `files` create (`create type ... as enum`), as `schema.type`. */
export function declaredEnums(
  files: readonly { readonly text: string }[],
): ReadonlySet<string> {
  return new Set(
    files.flatMap((file) =>
      [...withoutComments(file.text).matchAll(ENUM)].map((match) =>
        qualified(match[1]!),
      ),
    ),
  );
}

export function closingParen(text: string, open: number): number {
  let depth = 0;
  let quote: string | undefined;

  for (let i = open; i < text.length; i += 1) {
    const char = text[i]!;

    if (quote) {
      if (char === quote) {
        quote = undefined;
      }
    } else if (char === "'" || char === '"') {
      quote = char;
    } else if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;

      if (depth === 0) {
        return i;
      }
    }
  }

  return -1;
}

export function splitTopLevel(text: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let quote: string | undefined;
  let start = 0;

  for (let i = 0; i < text.length; i += 1) {
    const char = text[i]!;

    if (quote) {
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
      parts.push(text.slice(start, i).trim());
      start = i + 1;
    }
  }

  const last = text.slice(start).trim();

  if (last !== "") {
    parts.push(last);
  }

  return parts;
}

/**
 * The privileges the permissive policies in `files` imply, per table and role:
 * `for all` gives the four commands, `to public` (or no `to`) counts for
 * `authenticated` only, so `anon` needs a policy that names it. Restrictive
 * policies grant nothing. Only tables in `schemas` are kept.
 */
export function policyGrants(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): PolicyGrant[] {
  type Named = Map<
    string,
    { roles: PolicyGrant["role"][]; privileges: readonly string[] }
  >;

  const policies = new Map<string, Named>();

  for (const file of files) {
    const text = withoutComments(file.text);
    inOrder([
      [...text.matchAll(POLICY)].map((match) => ({
        index: match.index,
        apply: () => {
          const table = qualified(match[2]!);

          if (!schemas.includes(table.slice(0, table.indexOf(".")))) {
            return;
          }

          const clauses = match[3]!;

          if (/\bas\s+restrictive\b/i.test(clauses)) {
            return;
          }

          const command = /\bfor\s+(all|select|insert|update|delete)\b/i
            .exec(clauses)?.[1]
            ?.toLowerCase();

          const privileges =
            command === undefined || command === "all" ? COMMANDS : [command];

          const to = /\bto\s+([\s\S]+)$/i.exec(clauses)?.[1];

          const roles = (to ?? "public")
            .split(",")
            .map((role) => unquote(role.trim()))
            .map((role) => (role === "public" ? "authenticated" : role))
            .filter(
              (role): role is PolicyGrant["role"] =>
                role === "anon" || role === "authenticated",
            );

          const named: Named = policies.get(table) ?? new Map();
          named.set(unquote(match[1]!), { roles, privileges });
          policies.set(table, named);
        },
      })),
      [...text.matchAll(DROP_POLICY)].map((match) => ({
        index: match.index,
        apply: () => {
          policies.get(qualified(match[2]!))?.delete(unquote(match[1]!));
        },
      })),
      [...text.matchAll(DROP_TABLE)].map((match) => ({
        index: match.index,
        apply: () => {
          for (const table of droppedTables(match[1]!)) {
            policies.delete(table);
          }
        },
      })),
    ]);
  }

  const found = new Map<
    string,
    { table: string; role: PolicyGrant["role"]; privileges: Set<string> }
  >();

  for (const [table, named] of policies) {
    for (const { roles, privileges } of named.values()) {
      for (const role of roles) {
        const key = `${table}\u0000${role}`;

        const entry = found.get(key) ?? {
          table,
          role,
          privileges: new Set<string>(),
        };

        for (const privilege of privileges) {
          entry.privileges.add(privilege);
        }

        found.set(key, entry);
      }
    }
  }

  return [...found.values()]
    .map((entry): PolicyGrant => ({
      table: entry.table,
      role: entry.role,
      privileges: COMMANDS.filter((command) => entry.privileges.has(command)),
    }))
    .toSorted((a, b) =>
      a.table === b.table
        ? a.role < b.role
          ? -1
          : 1
        : a.table < b.table
          ? -1
          : 1,
    );
}

const EXTENSION = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+extension\s+(?:if\s+not\s+exists\s+)?(${NAME})(?:\s+with)?\s+schema\s+(${NAME})`,
  "gi",
);

const MODULE_FILE = /^-- @(?:bsb-block|bs-module) /m;

export function extensionSchema(
  sources: readonly { readonly text: string }[],
  extension: string,
): string | undefined {
  for (const source of sources) {
    if (MODULE_FILE.test(source.text)) {
      continue;
    }

    for (const match of withoutComments(source.text).matchAll(EXTENSION)) {
      if (unquote(match[1]!) === extension) {
        return unquote(match[2]!);
      }
    }
  }

  return undefined;
}

const TRIGGER_DEF = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+(${NAME})\s+(?:before|after)\s[^;]*?\bupdate\b[^;]*?\bon\s+(${TABLE_NAME})[^;]*?\bexecute\s+(?:function|procedure)\s+(${TABLE_NAME})\s*\(`,
  "gi",
);

const FUNCTION_DEF = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+(?:or\s+replace\s+)?function\s+(${TABLE_NAME})\s*\([\s\S]*?\bas\s+(\$\w*\$)([\s\S]*?)\2`,
  "gi",
);

/**
 * A trigger function that keeps `updated_at` current by its name, as the
 * `updated-at` module's `replace_equivalent_triggers` reads it.
 */
const UPDATED_AT_FUNCTION = /updated_at|moddatetime|touch/i;

const SETS_UPDATED_AT = /\bnew\s*\.\s*"?updated_at"?\s*:?=/i;

/**
 * The update trigger that keeps `updated_at` current on each table in `schemas`
 * the files create one on, by `schema.table`: its function is named like one
 * (`set_updated_at`, `moddatetime`, `touch_*`) or the files define it with
 * `new.updated_at :=`. Block triggers (`bsb_*`) don't count.
 */
export function declaredUpdatedAtTriggers(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): Readonly<Record<string, string>> {
  const texts = files.map((file) => withoutComments(file.text));
  const setters = new Set<string>();

  for (const text of texts) {
    for (const match of text.matchAll(FUNCTION_DEF)) {
      if (SETS_UPDATED_AT.test(match[3]!)) {
        setters.add(qualified(match[1]!));
      }
    }
  }

  const found: Record<string, string> = {};

  for (const text of texts) {
    for (const match of text.matchAll(TRIGGER_DEF)) {
      const name = unquote(match[1]!);
      const table = qualified(match[2]!);
      const fn = qualified(match[3]!);

      if (
        !name.startsWith("bsb_") &&
        schemas.includes(table.slice(0, table.indexOf("."))) &&
        (UPDATED_AT_FUNCTION.test(fn.slice(fn.indexOf(".") + 1)) ||
          setters.has(fn))
      ) {
        found[table] ??= name;
      }
    }
  }

  return found;
}

/** An index a `create index` statement builds. */
export interface IndexStatement {
  /** `schema.table`. */
  readonly table: string;
  readonly unique: boolean;
  /** `btree` unless the statement names another access method. */
  readonly method: string;
  /** Whether it has a `where`. */
  readonly partial: boolean;
  /** The plain columns it leads with, up to the first expression or option. */
  readonly columns: readonly string[];
  /** Whether every key is a plain column. */
  readonly plain: boolean;
}

const INDEX_DEF = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+(unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?(?:(?!on\b)${NAME}\s+)?on\s+(?:only\s+)?(${TABLE_NAME})\s*(?:using\s+(\w+)\s*)?\(`,
  "gi",
);

const PLAIN_KEY = /* @__PURE__ */ new RegExp(
  String.raw`^(${NAME})(?:\s+(?:asc|desc))?(?:\s+nulls\s+(?:first|last))?$`,
  "i",
);

/** The plain leading columns of an index key list, and whether all are plain. */
function indexKeys(list: string): {
  readonly columns: readonly string[];
  readonly plain: boolean;
} {
  const columns: string[] = [];

  for (const part of splitTopLevel(list)) {
    const key = PLAIN_KEY.exec(part.trim());

    if (key === null) {
      return { columns, plain: false };
    }

    columns.push(unquote(key[1]!));
  }

  return { columns, plain: true };
}

/** Each `create index` in `text`, which has no comments. */
export function indexStatements(text: string): IndexStatement[] {
  return [...text.matchAll(INDEX_DEF)].flatMap((match): IndexStatement[] => {
    const open = match.index + match[0].length - 1;
    const close = closingParen(text, open);

    if (close === -1) {
      return [];
    }

    const end = text.indexOf(";", close);
    const rest = text.slice(close + 1, end === -1 ? text.length : end);

    return [
      {
        table: qualified(match[2]!),
        unique: match[1] !== undefined,
        method: (match[3] ?? "btree").toLowerCase(),
        partial: /\bwhere\b/i.test(rest),
        ...indexKeys(text.slice(open + 1, close)),
      },
    ];
  });
}

const KEY_CONSTRAINT =
  /^(?:constraint\s+\S+\s+)?(?:primary\s+key|unique)\s*\(/i;

const COLUMN_KEY = /\s(?:primary\s+key|unique)\b/i;

/**
 * The leading columns of every full btree index the files give each table in
 * `schemas`: `create index` statements, and the primary keys and unique
 * constraints in `create table`. Partial indexes and other methods are left
 * out, since they don't answer every lookup.
 */
export function declaredIndexes(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): ReadonlyMap<string, readonly (readonly string[])[]> {
  const found = new Map<string, (readonly string[])[]>();

  const add = (table: string, columns: readonly string[]): void => {
    if (
      columns.length > 0 &&
      schemas.includes(table.slice(0, table.indexOf(".")))
    ) {
      found.set(table, [...(found.get(table) ?? []), columns]);
    }
  };

  for (const file of files) {
    const text = withoutComments(file.text);

    for (const index of indexStatements(text)) {
      if (!index.partial && index.method === "btree") {
        add(index.table, index.columns);
      }
    }

    for (const match of text.matchAll(TABLE)) {
      const table = qualified(match[1]!);
      const open = match.index + match[0].length - 1;
      const close = closingParen(text, open);

      if (close === -1) {
        continue;
      }

      for (const part of splitTopLevel(text.slice(open + 1, close))) {
        const definition = part.trim();
        const key = KEY_CONSTRAINT.exec(definition);

        if (key !== null) {
          const keyOpen = key.index + key[0].length - 1;
          const keyClose = closingParen(definition, keyOpen);

          add(
            table,
            indexKeys(definition.slice(keyOpen + 1, keyClose)).columns,
          );
        } else if (
          !TABLE_CONSTRAINT.test(definition) &&
          COLUMN_KEY.test(definition)
        ) {
          const first = new RegExp(`^${NAME}`).exec(definition)?.[0];

          if (first !== undefined) {
            add(table, [unquote(first)]);
          }
        }
      }
    }
  }

  return found;
}
