import type { ResolvedConfig } from "../../config/index.ts";
import type { BsbTag, TableFeature } from "../../sql/index.ts";

import { setTableFeature } from "../../sql/index.ts";
import { subjectTagArgs } from "../subject-tag.ts";

/** One file `migrate schema-first` writes, relative to the schemas folder. */
export interface SchemaFirstFile {
  readonly path: string;
  readonly contents: string;
}

const NAME = String.raw`(?:"?public"?\.)?"?([a-z_][a-z0-9_]*)"?`;

const TABLE_TARGETS: readonly RegExp[] = [
  new RegExp(
    String.raw`^create\s+table\s+(?:if\s+not\s+exists\s+)?${NAME}`,
    "iu",
  ),
  new RegExp(
    String.raw`^alter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?${NAME}`,
    "iu",
  ),
  new RegExp(
    String.raw`^create\s+(?:unique\s+)?index\s+(?:if\s+not\s+exists\s+)?\S+\s+on\s+(?:only\s+)?${NAME}`,
    "iu",
  ),
  new RegExp(
    String.raw`^create\s+policy\s+(?:"[^"]+"|\S+)\s+on\s+${NAME}`,
    "iu",
  ),
  new RegExp(
    String.raw`^drop\s+policy\s+(?:if\s+exists\s+)?(?:"[^"]+"|\S+)\s+on\s+${NAME}`,
    "iu",
  ),
  new RegExp(
    String.raw`^create\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+\S+[\s\S]*?\son\s+${NAME}\s`,
    "iu",
  ),
  new RegExp(
    String.raw`^(?:grant|revoke)\s[\s\S]*?\son\s+(?:table\s+)?${NAME}\s+(?:to|from)\s`,
    "iu",
  ),
  new RegExp(String.raw`^comment\s+on\s+table\s+${NAME}\s+is`, "iu"),
  new RegExp(
    String.raw`^drop\s+trigger\s+(?:if\s+exists\s+)?\S+\s+on\s+${NAME}`,
    "iu",
  ),
];

/** Statements about a view that sit next to its `create view`. */
const VIEW_TARGETS: readonly RegExp[] = [
  new RegExp(
    String.raw`^(?:grant|revoke)\s[\s\S]*?\son\s+(?:table\s+)?${NAME}\s+(?:to|from)\s`,
    "iu",
  ),
  new RegExp(String.raw`^comment\s+on\s+view\s+${NAME}\s+is`, "iu"),
  new RegExp(String.raw`^alter\s+view\s+(?:if\s+exists\s+)?${NAME}`, "iu"),
];

const DROP_VIEW = new RegExp(
  String.raw`^drop\s+view\s+(?:if\s+exists\s+)?${NAME}`,
  "iu",
);

const VIEW = new RegExp(
  String.raw`^create\s+(?:or\s+replace\s+)?view\s+${NAME}`,
  "iu",
);

/** The statement without its leading comment lines. */
function bare(statement: string): string {
  return statement.replace(LEADING_COMMENTS, "").trim();
}

const LEADING_COMMENTS = /^(?:\s*--[^\n]*\n)+/u;
const DOLLAR_TAG = /^\$[A-Za-z_]*\$/u;

/**
 * The statements of `sql`, split at semicolons outside quotes, dollar quotes
 * and comments.
 */
function statements(sql: string): string[] {
  const found: string[] = [];
  let start = 0;
  let at = 0;

  while (at < sql.length) {
    const char = sql[at];

    if (char === "-" && sql[at + 1] === "-") {
      const end = sql.indexOf("\n", at);
      at = end === -1 ? sql.length : end;
    } else if (char === "/" && sql[at + 1] === "*") {
      const end = sql.indexOf("*/", at + 2);
      at = end === -1 ? sql.length : end + 2;
    } else if (char === "'" || char === '"') {
      let end = at + 1;

      while (end < sql.length && sql[end] !== char) {
        end += 1;
      }

      at = end + 1;
    } else if (char === "$") {
      const tag = DOLLAR_TAG.exec(sql.slice(at))?.[0];

      if (tag === undefined) {
        at += 1;
      } else {
        const end = sql.indexOf(tag, at + tag.length);
        at = end === -1 ? sql.length : end + tag.length;
      }
    } else if (char === ";") {
      found.push(sql.slice(start, at + 1));
      start = at + 1;
      at += 1;
    } else {
      at += 1;
    }
  }

  if (sql.slice(start).trim() !== "") {
    found.push(sql.slice(start));
  }

  return found;
}

/** The table or view a statement belongs to, or undefined for anything else. */
function targetOf(
  statement: string,
  tables: ReadonlySet<string>,
  views: ReadonlySet<string>,
):
  | { readonly kind: "table" | "view" | "dropped"; readonly name: string }
  | undefined {
  const text = statement;

  for (const pattern of TABLE_TARGETS) {
    const name = pattern.exec(text)?.[1];

    if (name !== undefined && tables.has(name)) {
      return { kind: "table", name };
    }
  }

  const dropped = DROP_VIEW.exec(text)?.[1];

  if (dropped !== undefined && views.has(dropped)) {
    return { kind: "dropped", name: dropped };
  }

  for (const pattern of VIEW_TARGETS) {
    const name = pattern.exec(text)?.[1];

    if (name !== undefined && views.has(name)) {
      return { kind: "view", name };
    }
  }

  const view = VIEW.exec(text)?.[1];

  return view === undefined ? undefined : { kind: "view", name: view };
}

/**
 * The tags `config` implies for `table`: `subject`, `realtime`,
 * `vector-search`, `json`, `encrypted`, `lookup`, `server` and `events`.
 * `audit`, `audit-reads` and `expose` change the table's SQL only, which the
 * split keeps as written.
 */
function tagsFor(
  config: ResolvedConfig,
  table: string,
): { readonly feature: TableFeature; readonly tag: BsbTag }[] {
  const tags: { readonly feature: TableFeature; readonly tag: BsbTag }[] = [];

  for (const [type, subject] of Object.entries(config.subjects)) {
    if (subject.table === table || subject.table === `public.${table}`) {
      const args = subjectTagArgs(type, subject, table);

      if (args !== undefined) {
        tags.push({ feature: "subject", tag: { name: "subject", args } });
      }
    }
  }

  if (
    config.realtime.tables.some(
      (each) => each === table || each === `public.${table}`,
    )
  ) {
    const user = config.realtime.users[table];

    tags.push({
      feature: "realtime",
      tag: {
        name: "realtime",
        args: {
          ...(config.realtime.global.includes(table)
            ? { global: true as const }
            : {}),
          ...(user === undefined ? {} : { user }),
        },
      },
    });
  }

  const vector = config.vectorSearch.find(
    (each) => each.table === table || each.table === `public.${table}`,
  );

  if (vector !== undefined) {
    tags.push({
      feature: "vector-search",
      tag: {
        name: "vector-search",
        args: { column: vector.column, distance: vector.distance },
      },
    });
  }

  const jsonArgs: Record<string, string> = {};

  for (const [key, entry] of Object.entries(config.json)) {
    const column = [`${table}.`, `public.${table}.`]
      .map((prefix) => (key.startsWith(prefix) ? key.slice(prefix.length) : ""))
      .find((name) => name !== "" && !name.includes("."));

    if (column !== undefined) {
      jsonArgs[column] =
        "import" in entry ? `import:${entry.import}` : entry.type;
    }
  }

  if (Object.keys(jsonArgs).length > 0) {
    tags.push({ feature: "json", tag: { name: "json", args: jsonArgs } });
  }

  const app = config.appTables[table];

  const sealed = Object.entries(app?.columns ?? {}).flatMap(([name, column]) =>
    column.encrypted === true ? [[name, column.type] as const] : [],
  );

  if (sealed.length > 0) {
    tags.push({
      feature: "encrypted",
      tag: { name: "encrypted", args: Object.fromEntries(sealed) },
    });
  }

  const hashed = Object.entries(app?.columns ?? {}).flatMap(([name, column]) =>
    column.encrypted === true && column.lookup === true ? [name] : [],
  );

  if (hashed.length > 0) {
    tags.push({
      feature: "lookup",
      tag: {
        name: "lookup",
        args: Object.fromEntries(hashed.map((name) => [name, true as const])),
      },
    });
  }

  const hidden = Object.entries(app?.columns ?? {}).flatMap(([name, column]) =>
    column.access === "server" ? [name] : [],
  );

  if (hidden.length > 0) {
    tags.push({
      feature: "server",
      tag: {
        name: "server",
        args: Object.fromEntries(hidden.map((name) => [name, true as const])),
      },
    });
  }

  const events = app?.events;

  if (events !== undefined) {
    const on = events === true ? undefined : events.on;
    const include = events === true ? undefined : events.include;

    tags.push({
      feature: "events",
      tag: {
        name: "events",
        args: {
          ...(on === undefined ? {} : { on: on.join(", ") }),
          ...(include === undefined ? {} : { include: include.join(", ") }),
        },
      },
    });
  }

  return tags;
}

function header(text: string): string {
  return `-- ${text}\n`;
}

/**
 * Splits the rendered app tables file into the pg-delta export layout (ADR
 * 0102): `public/tables/<name>.sql` holds a table's create, columns, keys,
 * policies, grants, indexes and triggers, with the table's `@bsb` tags in its
 * comment; `public/views/<name>.sql` holds each view; every other statement
 * goes to `public/_custom/app_tables.sql`. Statements keep their order within a
 * file. `tables` is the app table names.
 */
export function splitAppTables(
  config: ResolvedConfig,
  sql: string,
  tables: readonly string[],
): SchemaFirstFile[] {
  const known = new Set(tables);
  const all = statements(sql).map((raw) => bare(raw));

  const views = new Set(
    all.flatMap((statement) => {
      const name = VIEW.exec(statement)?.[1];

      return name === undefined ? [] : [name];
    }),
  );

  const byTable = new Map<string, string[]>();
  const byView = new Map<string, string[]>();
  const rest: string[] = [];

  for (const statement of all) {
    if (statement === "") {
      continue;
    }

    const target = targetOf(statement, known, views);

    if (target === undefined) {
      rest.push(statement);
    } else if (target.kind !== "dropped") {
      const group = target.kind === "table" ? byTable : byView;
      group.set(target.name, [...(group.get(target.name) ?? []), statement]);
    }
  }

  const files: SchemaFirstFile[] = [];

  for (const name of tables) {
    const body = `${(byTable.get(name) ?? []).join("\n\n")}\n`;

    const tagged = tagsFor(config, name).reduce(
      (text, { feature, tag }) =>
        setTableFeature(text, "public", name, feature, true, tag),
      body,
    );

    files.push({
      path: `public/tables/${name}.sql`,
      contents: `${header("Owned by you since `better-supabase migrate schema-first`.")}${tagged}`,
    });
  }

  for (const [name, statements] of byView) {
    files.push({
      path: `public/views/${name}.sql`,
      contents: `${statements.join("\n\n")}\n`,
    });
  }

  if (rest.length > 0) {
    files.push({
      path: "public/_custom/app_tables.sql",
      contents: `${header("Statements of the old app tables file that belong to no single table.")}${rest.join("\n\n")}\n`,
    });
  }

  return files;
}
