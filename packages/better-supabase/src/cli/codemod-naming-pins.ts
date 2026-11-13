import type { ResolvedConfig } from "../config/index.ts";
import type { NamingRename } from "./codemod-naming.ts";

import { LEGACY_OPTION, moduleContext, SQL_MODULES } from "../sql/index.ts";
import { codeRanges } from "./code-ranges.ts";
import { closing as closingBrace } from "./codemod-config.ts";
import { isRecord } from "./guards.ts";

/** One `blocks.<block>.columns.<table>.<column>` entry that keeps an old name. */
export interface ColumnPin {
  /** The config key: a block, or an instance that installs the block. */
  readonly block: string;
  /** The SQL module the pin reads names from. */
  readonly module: string;
  readonly table: string;
  readonly column: string;
  /** The column's name before the rename, which the app's own table still has. */
  readonly name: string;
  /** `schema.table` the app's files own. */
  readonly physical: string;
}

/**
 * An `options.machines.<name>.history.actor` pin. The history default is
 * `actor_id` (`state-machine-options.ts`); an app table that still has
 * `actor_user_id` keeps that name.
 */
export interface HistoryPin {
  readonly block: string;
  readonly machine: string;
  readonly actor: string;
}

/** Column pins, history pins, and blocks whose context refused the config. */
export interface PinReport {
  readonly pins: readonly ColumnPin[];
  readonly history: readonly HistoryPin[];
  readonly review: readonly string[];
}

/**
 * Tenant columns a rename must not touch. `global` is `sql.tenantColumn`, which
 * every table shares. `byTable` is `columns.<table>.tenant`, and it applies
 * only to that table.
 */
export interface TenantColumnSkip {
  readonly global: ReadonlySet<string>;
  readonly byTable: ReadonlyMap<string, ReadonlySet<string>>;
}

/** A global name set, or a per-table skip. */
export type ColumnSkip = ReadonlySet<string> | TenantColumnSkip;

interface PinTarget {
  readonly key: string;
  readonly module: string;
  readonly instance?: string;
  readonly options?: unknown;
  readonly columns?: unknown;
}

interface Span {
  readonly open: number;
  readonly end: number;
}

const SQL_WORDS: ReadonlySet<string> = new Set([
  "and",
  "as",
  "delete",
  "from",
  "full",
  "group",
  "inner",
  "insert",
  "into",
  "join",
  "left",
  "limit",
  "not",
  "offset",
  "on",
  "only",
  "or",
  "order",
  "returning",
  "right",
  "select",
  "set",
  "table",
  "union",
  "update",
  "using",
  "values",
  "where",
]);

const escapeRegExp = (value: string): string =>
  value.replaceAll(/[.*+?^${}()|[\]\\]/g, String.raw`\$&`);

const qualify = (table: string): string =>
  table.includes(".") ? table : `public.${table}`;

/**
 * The line a pin asks the reader to add. `codemod naming` and `codemod
 * owned-columns` both use it.
 */
export function pinReview(pin: ColumnPin): string {
  return `Your table keeps "${pin.name}", which 0.58 names differently. Add \`columns: { ${pin.table}: { ${pin.column}: "${pin.name}" } }\` to blocks.${pin.block}.`;
}

function targets(config: {
  readonly blocks: ResolvedConfig["blocks"];
  readonly instances?: ResolvedConfig["instances"];
}): PinTarget[] {
  const list: PinTarget[] = [];

  for (const [key, block] of Object.entries(config.blocks)) {
    if (block !== undefined) {
      list.push({
        key,
        module: key,
        options: block.options,
        columns: block.columns,
      });
    }
  }

  for (const [key, instance] of Object.entries(config.instances ?? {})) {
    if (config.blocks[key] !== undefined && instance.block === key) {
      continue;
    }

    list.push({
      key,
      module: instance.block,
      instance: key,
      options: instance.config.options,
      columns: instance.config.columns,
    });
  }

  return list;
}

/**
 * `block` without the options 0.58 removed (`extraColumns` and its prefixed
 * forms, `uniqueNumber`). They name no table or column, and later codemods move
 * them, so a pin does not wait for them.
 */
function withoutRemovedOptions<T extends { readonly options?: unknown }>(
  block: T,
): T {
  if (!isRecord(block.options)) {
    return block;
  }

  return {
    ...block,
    options: Object.fromEntries(
      Object.entries(block.options).filter(
        ([key]) => !LEGACY_OPTION.test(key) && key !== "uniqueNumber",
      ),
    ),
  };
}

function historyPins(
  target: PinTarget,
  ownColumns: Readonly<Record<string, readonly string[]>>,
): HistoryPin[] {
  const options = target.options;

  if (!isRecord(options) || !isRecord(options["machines"])) {
    return [];
  }

  const found: HistoryPin[] = [];

  for (const [machine, entry] of Object.entries(options["machines"])) {
    if (!isRecord(entry) || !isRecord(entry["history"])) {
      continue;
    }

    const history = entry["history"];
    const table = history["table"];

    if (typeof table !== "string" || history["actor"] !== undefined) {
      continue;
    }

    const has = ownColumns[qualify(table)];

    if (has?.includes("actor_user_id") === true && !has.includes("actor_id")) {
      found.push({ block: target.key, machine, actor: "actor_user_id" });
    }
  }

  return found;
}

/**
 * The columns of the app's own tables that the rename table renames and that
 * still carry the old name, plus history actor pins and a review line for each
 * block whose context refuses the config. `ownColumns` is the app's columns by
 * `schema.table`.
 */
export function columnPins(
  config: {
    readonly blocks: ResolvedConfig["blocks"];
    readonly instances?: ResolvedConfig["instances"];
    readonly sql?: Pick<ResolvedConfig["sql"], "tenantColumn">;
  },
  renames: readonly NamingRename[],
  ownTables: Readonly<Record<string, string>>,
  ownColumns: Readonly<Record<string, readonly string[]>>,
): PinReport {
  const pins: ColumnPin[] = [];
  const history: HistoryPin[] = [];
  const review: string[] = [];
  const list = targets(config);

  const installed = [
    ...new Set([
      ...Object.keys(config.blocks),
      ...Object.values(config.instances ?? {}).map(
        (instance) => instance.block,
      ),
    ]),
  ];

  const layout = {
    modules: Object.fromEntries(
      Object.entries(config.blocks).map(([key, block]) => [
        key,
        block === undefined ? block : withoutRemovedOptions(block),
      ]),
    ),
    ownTables,
    ...(config.sql?.tenantColumn === undefined
      ? {}
      : { blockTenantColumn: config.sql.tenantColumn }),
    ...(config.instances === undefined
      ? {}
      : {
          instances: Object.fromEntries(
            Object.entries(config.instances).map(([key, instance]) => [
              key,
              { ...instance, config: withoutRemovedOptions(instance.config) },
            ]),
          ),
        }),
  };

  for (const target of list) {
    history.push(...historyPins(target, ownColumns));

    const names = SQL_MODULES[target.module]?.names;

    if (names === undefined) {
      continue;
    }

    let ctx: ReturnType<typeof moduleContext>;

    try {
      ctx = moduleContext(target.module, layout, installed, target.instance);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);

      review.push(
        `blocks.${target.key}: ${message} Column pins for this block were left out. Fix the config and run \`better-supabase codemod naming\` again.`,
      );
      continue;
    }

    // SAFETY: a block config's `columns` maps logical tables to logical columns.
    const configured = (target.columns ?? {}) as Readonly<
      Record<string, Readonly<Record<string, string | null> | undefined>>
    >;

    for (const table of ctx.appOwned) {
      const spec = names.tables[table];

      if (spec === undefined) {
        continue;
      }

      const parts = ctx.tableName(table);
      const physical = `${parts.schema}.${parts.name}`;
      const has = ownColumns[physical];

      if (has === undefined) {
        continue;
      }

      for (const [column, to] of Object.entries(spec.columns)) {
        const rename = renames.find(
          (candidate) =>
            candidate.kind === "column" &&
            candidate.to === to &&
            candidate.table?.split(".").at(-1) === spec.name,
        );

        if (
          rename !== undefined &&
          configured[table]?.[column] === undefined &&
          !(column === "tenant" && rename.from === config.sql?.tenantColumn) &&
          has.includes(rename.from) &&
          !has.includes(rename.to)
        ) {
          pins.push({
            block: target.key,
            module: target.module,
            table,
            column,
            name: rename.from,
            physical,
          });
        }
      }
    }
  }

  return { pins, history, review };
}

function codeIn(
  ranges: readonly [number, number][],
): (index: number) => boolean {
  return (index) =>
    ranges.some(([start, end]) => index >= start && index < end);
}

function findKeyObject(
  text: string,
  key: string,
  code: (index: number) => boolean,
  within?: Span,
): Span | undefined {
  const escaped = escapeRegExp(key);

  const pattern = new RegExp(
    `(?:^|[\\s,{])(?:"${escaped}"|${escaped})\\s*:\\s*\\{`,
    "g",
  );

  const from = within?.open ?? 0;
  const to = within?.end ?? text.length;

  for (const match of text.matchAll(pattern)) {
    if (match.index < from) {
      continue;
    }

    if (match.index >= to) {
      break;
    }

    const open = match.index + match[0].length - 1;

    if (!code(open)) {
      continue;
    }

    const end = closingBrace(text, open, code);

    if (end === -1 || end > to) {
      continue;
    }

    return { open, end };
  }

  return undefined;
}

/** The indent of the object body: the next line's, or two spaces deeper. */
function bodyIndent(text: string, open: number): string {
  const lineStart = text.lastIndexOf("\n", open - 1) + 1;
  const lineIndent = /^[ \t]*/.exec(text.slice(lineStart))?.[0] ?? "";
  const next = text.indexOf("\n", open);

  if (next !== -1) {
    const nextIndent = /^[ \t]*/.exec(text.slice(next + 1))?.[0] ?? "";

    if (nextIndent.length > lineIndent.length) {
      return nextIndent;
    }
  }

  return `${lineIndent}  `;
}

function insertProperty(text: string, open: number, property: string): string {
  const indent = bodyIndent(text, open);

  return `${text.slice(0, open + 1)}\n${indent}${property},${text.slice(open + 1)}`;
}

function rootFor(
  text: string,
  code: (index: number) => boolean,
  key: string,
): Span | undefined {
  const blocks = findKeyObject(text, "blocks", code);

  const inBlocks =
    blocks === undefined ? undefined : findKeyObject(text, key, code, blocks);

  if (inBlocks !== undefined) {
    return inBlocks;
  }

  const instances = findKeyObject(text, "instances", code);

  return instances === undefined
    ? undefined
    : findKeyObject(text, key, code, instances);
}

/**
 * `text` with each pin added under `<block>: { columns: { <table>: { ... } }
 * }`, one entry per line, at the indent of the next line. Only the `blocks`
 * object (then `instances`) is searched. Returns the pins it found no object
 * for, which the user adds by hand.
 */
export function withColumnPins(
  text: string,
  pins: readonly ColumnPin[],
): { readonly text: string; readonly missed: readonly ColumnPin[] } {
  let out = text;
  const missed: ColumnPin[] = [];

  for (const pin of pins) {
    const ranges = codeRanges(out);
    const code = codeIn(ranges);
    const block = rootFor(out, code, pin.block);

    if (block === undefined) {
      missed.push(pin);
      continue;
    }

    const entry = `${pin.column}: "${pin.name}"`;
    const columns = findKeyObject(out, "columns", code, block);

    if (columns === undefined) {
      const indent = bodyIndent(out, block.open);
      const row = `${indent}  `;
      const field = `${row}  `;

      out = `${out.slice(0, block.open + 1)}\n${indent}columns: {\n${row}${pin.table}: {\n${field}${entry},\n${row}},\n${indent}},${out.slice(block.open + 1)}`;
      continue;
    }

    const table = findKeyObject(out, pin.table, code, columns);

    if (table === undefined) {
      const indent = bodyIndent(out, columns.open);
      const field = `${indent}  `;

      out = `${out.slice(0, columns.open + 1)}\n${indent}${pin.table}: {\n${field}${entry},\n${indent}},${out.slice(columns.open + 1)}`;
      continue;
    }

    out = insertProperty(out, table.open, entry);
  }

  return { text: out, missed };
}

/**
 * `text` with each history actor pin written into
 * `options.machines.<machine>.history`, one entry per line.
 */
export function withHistoryPins(
  text: string,
  pins: readonly HistoryPin[],
): { readonly text: string; readonly missed: readonly HistoryPin[] } {
  let out = text;
  const missed: HistoryPin[] = [];

  for (const pin of pins) {
    const ranges = codeRanges(out);
    const code = codeIn(ranges);
    const block = rootFor(out, code, pin.block);

    const options =
      block === undefined
        ? undefined
        : findKeyObject(out, "options", code, block);

    const machines =
      options === undefined
        ? undefined
        : findKeyObject(out, "machines", code, options);

    const machine =
      machines === undefined
        ? undefined
        : findKeyObject(out, pin.machine, code, machines);

    const history =
      machine === undefined
        ? undefined
        : findKeyObject(out, "history", code, machine);

    if (history === undefined) {
      missed.push(pin);
      continue;
    }

    if (/\bactor\s*:/.test(out.slice(history.open, history.end))) {
      continue;
    }

    out = insertProperty(out, history.open, `actor: "${pin.actor}"`);
  }

  return { text: out, missed };
}

function isTenantSkip(skip: ColumnSkip): skip is TenantColumnSkip {
  return "byTable" in skip;
}

function columnSkipped(rename: NamingRename, skip: ColumnSkip): boolean {
  if (!isTenantSkip(skip)) {
    return skip.has(rename.from);
  }

  if (skip.global.has(rename.from)) {
    return true;
  }

  return (
    rename.table !== undefined &&
    skip.byTable.get(rename.table)?.has(rename.from) === true
  );
}

function sqlSegments(
  sql: string,
): { readonly dollar: boolean; readonly text: string }[] {
  const out: { dollar: boolean; text: string }[] = [];
  let start = 0;
  let index = 0;

  while (index < sql.length) {
    if (sql[index] !== "$") {
      index += 1;
      continue;
    }

    const match = /^\$[A-Za-z0-9_]*\$/.exec(sql.slice(index));

    if (match === null) {
      index += 1;
      continue;
    }

    const tag = match[0];
    const end = sql.indexOf(tag, index + tag.length);

    if (end === -1) {
      index += 1;
      continue;
    }

    if (index > start) {
      out.push({ dollar: false, text: sql.slice(start, index) });
    }

    const close = end + tag.length;

    out.push({ dollar: true, text: sql.slice(index, close) });
    index = close;
    start = close;
  }

  if (start < sql.length) {
    out.push({ dollar: false, text: sql.slice(start) });
  }

  return out;
}

function maskSqlStrings(sql: string): {
  readonly text: string;
  readonly strings: readonly string[];
} {
  const strings: string[] = [];

  const text = sql.replaceAll(/'(?:[^']|'')*'/g, (whole) => {
    const token = `«${String(strings.length)}»`;

    strings.push(whole);

    return token;
  });

  return { text, strings };
}

function unmaskSqlStrings(text: string, strings: readonly string[]): string {
  return text.replaceAll(
    /«(\d+)»/g,
    (_whole, index: string) => strings[Number(index)] ?? "",
  );
}

function tableParts(
  rename: NamingRename,
): { readonly schema: string; readonly name: string } | undefined {
  const [schema, name] = rename.table?.split(".") ?? [];

  if (schema === undefined || name === undefined) {
    return undefined;
  }

  return { schema, name };
}

/** Rewrites `'{...}'` arguments of `better_supabase.audit` for `rename`. */
function renameAuditCalls(sql: string, rename: NamingRename): string {
  const parts = tableParts(rename);

  if (parts === undefined) {
    return sql;
  }

  const wanted = `${parts.schema}.${parts.name}`;
  let out = "";
  let from = 0;
  const calls = sql.matchAll(/better_supabase\.audit\s*\(\s*'([^']*)'/gi);

  for (const match of calls) {
    const normalized = match[1]?.replaceAll('"', "") ?? "";

    if (normalized !== wanted && normalized !== parts.name) {
      continue;
    }

    const argsAt = match.index + match[0].length;
    const close = sql.indexOf(")", argsAt);

    if (close === -1) {
      continue;
    }

    const args = sql.slice(argsAt, close);

    const renamed = args.replaceAll(
      /'\{([^}]*)\}'/g,
      (_array, inner: string) => {
        const names = inner.split(",").map((part) => part.trim());

        return `'{${names.map((part) => (part === rename.from ? rename.to : part)).join(", ")}}'`;
      },
    );

    out += sql.slice(from, argsAt) + renamed;
    from = close;
  }

  return out + sql.slice(from);
}

function aliasesOf(
  sql: string,
  schema: string,
  name: string,
): ReadonlySet<string> {
  const pattern = new RegExp(
    String.raw`"?${escapeRegExp(schema)}"?\s*\.\s*"?${escapeRegExp(name)}"?\s+(?:as\s+)?("?[A-Za-z_][\w$]*"?)`,
    "gi",
  );

  const found = new Set<string>();

  for (const match of sql.matchAll(pattern)) {
    const alias = match[1]?.replaceAll('"', "") ?? "";

    if (!SQL_WORDS.has(alias.toLowerCase())) {
      found.add(alias);
    }
  }

  return found;
}

function renameIdent(text: string, from: string, to: string): string {
  return text.replaceAll(
    new RegExp(String.raw`(?<![\w$"])"?${escapeRegExp(from)}"?`, "g"),
    (whole) => (whole.startsWith('"') ? `"${to}"` : to),
  );
}

function renameQualified(
  sql: string,
  schema: string,
  name: string,
  from: string,
  to: string,
  aliases: ReadonlySet<string>,
): string {
  const heads = [name, ...aliases].map(escapeRegExp).join("|");

  return sql.replaceAll(
    new RegExp(
      String.raw`(?<![\w$"])("?(?:${escapeRegExp(schema)}"?\s*\.\s*)?(?:${heads})"?)(\s*\.\s*)("?)${escapeRegExp(from)}\3(?![\w$"])`,
      "gi",
    ),
    (_whole, head: string, dot: string, quote: string) =>
      `${head}${dot}${quote}${to}${quote}`,
  );
}

function renameInsertList(
  sql: string,
  schema: string,
  name: string,
  from: string,
  to: string,
): string {
  return sql.replaceAll(
    new RegExp(
      String.raw`(\binsert\s+into\s+"?${escapeRegExp(schema)}"?\s*\.\s*"?${escapeRegExp(name)}"?\s*\()([^)]*)(\))`,
      "gi",
    ),
    (_whole, head: string, list: string, tail: string) =>
      `${head}${renameIdent(list, from, to)}${tail}`,
  );
}

function renameSetTargets(
  sql: string,
  schema: string,
  name: string,
  from: string,
  to: string,
): string {
  const pattern = new RegExp(
    String.raw`\bupdate\s+(?:only\s+)?"?${escapeRegExp(schema)}"?\s*\.\s*"?${escapeRegExp(name)}"?\s+(?:as\s+)?(?:(?!set\b)[A-Za-z_][\w$]*\s+)?set\s+`,
    "gi",
  );

  let out = "";
  let fromIndex = 0;

  for (const match of sql.matchAll(pattern)) {
    const start = match.index + match[0].length;
    const rest = sql.slice(start);
    const stop = /\b(?:where|from|returning)\b|;/i.exec(rest);
    const end = start + (stop?.index ?? rest.length);
    const clause = sql.slice(start, end);

    const next = clause.replaceAll(
      new RegExp(
        String.raw`(^|[,])(\s*)("?)${escapeRegExp(from)}\3(?=\s*=)`,
        "gi",
      ),
      (_whole, comma: string, space: string, quote: string) =>
        `${comma}${space}${quote}${to}${quote}`,
    );

    out += sql.slice(fromIndex, start) + next;
    fromIndex = end;
  }

  return out + sql.slice(fromIndex);
}

function renameSegment(
  sql: string,
  columns: readonly NamingRename[],
  skip: ColumnSkip,
): string {
  let audited = sql;

  for (const rename of columns) {
    if (!columnSkipped(rename, skip)) {
      audited = renameAuditCalls(audited, rename);
    }
  }

  const masked = maskSqlStrings(audited);
  let body = masked.text;

  for (const rename of columns) {
    if (columnSkipped(rename, skip)) {
      continue;
    }

    const parts = tableParts(rename);

    if (parts === undefined) {
      continue;
    }

    const aliases = aliasesOf(body, parts.schema, parts.name);

    body = renameQualified(
      body,
      parts.schema,
      parts.name,
      rename.from,
      rename.to,
      aliases,
    );
    body = renameInsertList(
      body,
      parts.schema,
      parts.name,
      rename.from,
      rename.to,
    );
    body = renameSetTargets(
      body,
      parts.schema,
      parts.name,
      rename.from,
      rename.to,
    );
  }

  return unmaskSqlStrings(body, masked.strings);
}

/**
 * `sql` with the column names of the `column` rows renamed where a statement
 * names the block table (`better_supabase.x`) or its alias, in that table's
 * insert column list or update `set` targets, and inside `'{...}'` arguments of
 * `better_supabase.audit` for that table. A `$$` body is left as it is, and so
 * is a string literal. Statements about the app's own tables keep their names.
 */
export function renameSqlColumns(
  sql: string,
  renames: readonly NamingRename[],
  skip: ColumnSkip = new Set(),
): string {
  const columns = renames.filter(
    (rename) =>
      rename.kind === "column" &&
      rename.table !== undefined &&
      !columnSkipped(rename, skip),
  );

  if (columns.length === 0 || !sql.includes("better_supabase")) {
    return sql;
  }

  return sqlSegments(sql)
    .map((segment) =>
      segment.dollar
        ? segment.text
        : renameSegment(segment.text, columns, skip),
    )
    .join("");
}
