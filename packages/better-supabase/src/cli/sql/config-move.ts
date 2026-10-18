/**
 * The 0.9 config move: `sql.modules` becomes the top-level `blocks` key.
 * The edit is textual, like the rest of `config-edit.ts`, so comments and
 * formatting around the moved property survive.
 */

import type { ConfigEdit, Property } from "./config-edit.ts";

import {
  closingIndex,
  configObject,
  indentAt,
  mask,
  properties,
  skipSpace,
} from "./config-edit.ts";

/** Where a property sits: the range to cut and its own text, without the comma. */
interface Span {
  readonly start: number;
  readonly end: number;
  /** From the first leading comment line to the value, then a trailing same-line comment. */
  readonly value: string;
  /** Where the key starts in `value`. */
  readonly keyAt: number;
  readonly trailing: string;
  readonly hasComma: boolean;
  readonly multiline: boolean;
}

const lineStart = (source: string, index: number): number =>
  source.lastIndexOf("\n", index - 1) + 1;

function propertySpan(
  source: string,
  code: string,
  open: number,
  props: readonly Property[],
  index: number,
): Span {
  const prop = props[index];
  const previous = props[index - 1];

  if (prop === undefined) {
    throw new Error(`no property at ${index}`);
  }

  const close = closingIndex(code, open);
  const multiline = code.slice(open, close).includes("\n");
  const after = skipSpace(code, prop.valueEnd);
  const hasComma = code[after] === ",";
  const tailFrom = hasComma ? after + 1 : prop.valueEnd;

  if (!multiline) {
    const value = source.slice(prop.start, prop.valueEnd);

    if (previous) {
      return {
        start: previous.valueEnd,
        end: prop.valueEnd,
        value,
        keyAt: 0,
        trailing: "",
        hasComma,
        multiline,
      };
    }

    return {
      start: prop.start,
      end: hasComma ? skipSpace(code, tailFrom) : prop.valueEnd,
      value,
      keyAt: 0,
      trailing: "",
      hasComma,
      multiline,
    };
  }

  let before = open + 1;

  if (previous) {
    const comma = skipSpace(code, previous.valueEnd);
    before = code[comma] === "," ? comma + 1 : previous.valueEnd;
  }

  const gap = source.slice(before, prop.start);
  const newline = gap.indexOf("\n");
  const start = newline === -1 ? prop.start : before + newline + 1;
  const lineEnd = source.indexOf("\n", tailFrom);

  const restIsBlank =
    lineEnd !== -1 && code.slice(tailFrom, lineEnd).trim() === "";

  return {
    start,
    end: restIsBlank ? lineEnd + 1 : tailFrom,
    value: source.slice(start, prop.valueEnd),
    keyAt: prop.start - start,
    trailing: restIsBlank ? source.slice(tailFrom, lineEnd).trimEnd() : "",
    hasComma,
    multiline,
  };
}

/** `modules: ...` as `blocks: ...`, keeping the key's quotes. */
function renameKey(text: string, keyAt: number, prop: Property): string {
  const head = text.slice(keyAt);
  const quoted = /^(["'])modules\1/.exec(head);

  if (quoted) {
    const quote = quoted[1] ?? '"';

    return `${text.slice(0, keyAt)}${quote}blocks${quote}${head.slice(quoted[0].length)}`;
  }

  // Shorthand `modules` names a variable: keep it as the value.
  if (prop.valueStart === prop.start) {
    return `${text.slice(0, keyAt)}blocks: modules${head.slice("modules".length)}`;
  }

  return `${text.slice(0, keyAt)}blocks${head.slice("modules".length)}`;
}

function reindent(text: string, from: string, to: string): string {
  return text
    .split("\n")
    .map((line) =>
      line.startsWith(from) ? to + line.slice(from.length) : line,
    )
    .join("\n");
}

/**
 * `source` with `sql.modules` moved to a top-level `blocks` key, placed
 * right after `sql`. `sql` is dropped when nothing else is left in it. A
 * config without `sql.modules` comes back unchanged; one that also sets
 * `blocks` is refused, because the two need a merge by hand.
 */
export function moveSqlModulesToBlocks(source: string): ConfigEdit {
  const code = mask(source);
  const root = configObject(code);

  if (root === undefined) {
    return /\bmodules\b/.test(code)
      ? {
          ok: false,
          reason: "it doesn't pass an object literal to defineConfig()",
        }
      : { ok: true, text: source };
  }

  const rootProps = properties(source, code, root);

  if (!rootProps) {
    return { ok: false, reason: "its config object can't be read" };
  }

  const sqlIndex = rootProps.findIndex((prop) => prop.key === "sql");
  const sql = rootProps[sqlIndex];

  if (sql === undefined) {
    return { ok: true, text: source };
  }

  if (code[sql.valueStart] !== "{" || sql.valueStart === sql.start) {
    return /\bmodules\b/.test(code)
      ? {
          ok: false,
          reason:
            "its `sql` value isn't an object literal; move `sql.modules` to `blocks` by hand",
        }
      : { ok: true, text: source };
  }

  const sqlProps = properties(source, code, sql.valueStart);

  if (!sqlProps) {
    return { ok: false, reason: "its `sql` object can't be read" };
  }

  const modulesIndex = sqlProps.findIndex((prop) => prop.key === "modules");
  const modules = sqlProps[modulesIndex];

  if (modules === undefined) {
    return { ok: true, text: source };
  }

  if (rootProps.some((prop) => prop.key === "blocks")) {
    return {
      ok: false,
      reason:
        "it sets both `sql.modules` and `blocks`; merge `sql.modules` into `blocks` by hand",
    };
  }

  const cut = propertySpan(
    source,
    code,
    sql.valueStart,
    sqlProps,
    modulesIndex,
  );

  const outer = propertySpan(source, code, root, rootProps, sqlIndex);
  const renamed = renameKey(cut.value, cut.keyAt, modules);

  const sqlClose = closingIndex(code, sql.valueStart);

  const leftover =
    source.slice(sql.valueStart + 1, cut.start) +
    source.slice(cut.end, sqlClose);

  const dropSql = sqlProps.length === 1 && leftover.trim() === "";

  if (!cut.multiline || !outer.multiline) {
    const property = renamed.trim();

    if (dropSql) {
      return {
        ok: true,
        text:
          source.slice(0, sql.start) + property + source.slice(sql.valueEnd),
      };
    }

    return {
      ok: true,
      text: `${source.slice(0, cut.start)}${source.slice(cut.end, sql.valueEnd)}, ${property}${source.slice(sql.valueEnd)}`,
    };
  }

  const sqlIndent = indentAt(source, sql.start);
  const body = reindent(renamed, indentAt(source, modules.start), sqlIndent);
  const firstLine = cut.start === modules.start ? sqlIndent + body : body;
  const moved = `${firstLine},${cut.trailing}\n`;

  if (dropSql) {
    return {
      ok: true,
      text:
        source.slice(0, lineStart(source, sql.start)) +
        moved +
        source.slice(outer.end),
    };
  }

  const atLineStart = source[outer.end - 1] === "\n";

  return {
    ok: true,
    text:
      source.slice(0, cut.start) +
      source.slice(cut.end, sql.valueEnd) +
      (outer.hasComma ? "" : ",") +
      source.slice(sql.valueEnd, outer.end) +
      (atLineStart ? "" : "\n") +
      moved +
      source.slice(outer.end),
  };
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** `moveSqlModulesToBlocks` for `better-supabase.config.json`. */
export function moveSqlModulesToBlocksJson(source: string): ConfigEdit {
  let config: unknown;

  try {
    config = JSON.parse(source);
  } catch {
    return { ok: false, reason: "it isn't valid JSON" };
  }

  if (!isRecord(config)) {
    return { ok: false, reason: "it isn't a JSON object" };
  }

  const sql = config["sql"];

  if (!isRecord(sql) || !("modules" in sql)) {
    return { ok: true, text: source };
  }

  if ("blocks" in config) {
    return {
      ok: false,
      reason:
        "it sets both `sql.modules` and `blocks`; merge `sql.modules` into `blocks` by hand",
    };
  }

  const { modules, ...restSql } = sql;
  const next: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(config)) {
    if (key !== "sql") {
      next[key] = value;
      continue;
    }

    if (Object.keys(restSql).length > 0) {
      next["sql"] = restSql;
    }

    next["blocks"] = modules;
  }

  const indent = /^[ \t]+/m.exec(source)?.[0] ?? "  ";

  return { ok: true, text: `${JSON.stringify(next, null, indent)}\n` };
}
