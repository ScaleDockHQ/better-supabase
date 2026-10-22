/**
 * The 0.15 block renames in a config: `blocks` keys and list entries,
 * `preset.blocks` entries and the operation names in
 * `auth.authorization.operations`. Like `config-group.ts`, the TypeScript edit
 * is textual so comments and formatting survive.
 */

import type { ConfigEdit } from "./config-edit.ts";

import { renamedBlock } from "../../sql/index.ts";
import { closingIndex, configObject, mask, properties } from "./config-edit.ts";

interface Edit {
  readonly start: number;
  readonly end: number;
  readonly text: string;
}

const ENVIRONMENT_KEY = /^\$(?:development|production|test|ci)$/;

const STRING = /(["'`])([a-z0-9-]+)\1/g;

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** An operation name (`<block>.<action>`) under its block's 0.15 name. */
export function currentOperationName(name: string): string {
  const dot = name.indexOf(".");
  const to = dot === -1 ? undefined : renamedBlock(name.slice(0, dot));

  return to === undefined ? name : `${to}${name.slice(dot)}`;
}

function applyEdits(source: string, edits: readonly Edit[]): string {
  let text = source;

  for (const edit of edits.toSorted((a, b) => b.start - a.start)) {
    text = text.slice(0, edit.start) + edit.text + text.slice(edit.end);
  }

  return text;
}

/** The key token at `start` renamed to `to`, keeping its quotes. */
function keyEdit(source: string, start: number, key: string, to: string): Edit {
  const quote = source[start];
  const quoted = quote === '"' || quote === "'";
  const bare = /^[A-Za-z_$][\w$]*$/.test(to);

  return {
    start,
    end: start + key.length + (quoted ? 2 : 0),
    text: quoted ? `${quote}${to}${quote}` : bare ? to : `"${to}"`,
  };
}

/** Edits renaming the keys of the object literal at `open` with `rename`. */
function keyEdits(
  source: string,
  code: string,
  open: number,
  rename: (key: string) => string,
): Edit[] {
  return (properties(source, code, open) ?? []).flatMap((prop) => {
    if (prop.key === undefined || prop.valueStart === prop.start) {
      return [];
    }

    const to = rename(prop.key);

    return to === prop.key ? [] : [keyEdit(source, prop.start, prop.key, to)];
  });
}

/**
 * Edits renaming the block names among the string literals of the array at
 * `open`.
 */
function listEdits(source: string, code: string, open: number): Edit[] {
  const close = closingIndex(code, open);

  if (close === -1) {
    return [];
  }

  return [...source.slice(open, close).matchAll(STRING)].flatMap((match) => {
    const to = renamedBlock(match[2]!);
    const start = open + match.index + 1;

    return to === undefined
      ? []
      : [{ start, end: start + match[2]!.length, text: to }];
  });
}

/** The value at `index` when it opens an object or an array. */
const opens = (code: string, index: number): "{" | "[" | undefined =>
  code[index] === "{" || code[index] === "[" ? code[index] : undefined;

/** The value of `key` in the object literal at `open`, when it is a literal. */
function valueOf(
  source: string,
  code: string,
  open: number,
  key: string,
): number | undefined {
  const prop = properties(source, code, open)?.find(
    (entry) => entry.key === key,
  );

  return prop === undefined || opens(code, prop.valueStart) === undefined
    ? undefined
    : prop.valueStart;
}

function objectEdits(source: string, code: string, open: number): Edit[] {
  const edits: Edit[] = [];

  for (const prop of properties(source, code, open) ?? []) {
    const kind = opens(code, prop.valueStart);

    if (prop.key === undefined || kind === undefined) {
      continue;
    }

    if (prop.key === "blocks") {
      edits.push(
        ...(kind === "["
          ? listEdits(source, code, prop.valueStart)
          : keyEdits(
              source,
              code,
              prop.valueStart,
              (key) => renamedBlock(key) ?? key,
            )),
      );
    } else if (prop.key === "preset" && kind === "{") {
      const blocks = valueOf(source, code, prop.valueStart, "blocks");

      if (blocks !== undefined && code[blocks] === "[") {
        edits.push(...listEdits(source, code, blocks));
      }
    } else if (prop.key === "auth" && kind === "{") {
      const authorization = valueOf(
        source,
        code,
        prop.valueStart,
        "authorization",
      );

      const operations =
        authorization !== undefined && code[authorization] === "{"
          ? valueOf(source, code, authorization, "operations")
          : undefined;

      if (operations !== undefined && code[operations] === "{") {
        edits.push(...keyEdits(source, code, operations, currentOperationName));
      }
    } else if (prop.key === "$env" && kind === "{") {
      for (const env of properties(source, code, prop.valueStart) ?? []) {
        if (code[env.valueStart] === "{") {
          edits.push(...objectEdits(source, code, env.valueStart));
        }
      }
    } else if (ENVIRONMENT_KEY.test(prop.key) && kind === "{") {
      edits.push(...objectEdits(source, code, prop.valueStart));
    }
  }

  return edits;
}

/** `better-supabase.config.ts`, grouped, with the 0.15 block names. */
export function renameBlocksInSource(source: string): ConfigEdit {
  const code = mask(source);
  const open = configObject(code);

  if (open === undefined) {
    return {
      ok: false,
      reason: "no defineConfig({...}) or default export object found",
    };
  }

  return {
    ok: true,
    text: applyEdits(source, objectEdits(source, code, open)),
  };
}

function renameKeys(value: unknown, rename: (key: string) => string): unknown {
  return isObject(value)
    ? Object.fromEntries(
        Object.entries(value).map(([key, entry]) => [rename(key), entry]),
      )
    : value;
}

const renameList = (value: unknown): unknown =>
  Array.isArray(value)
    ? value.map((entry: unknown) =>
        typeof entry === "string" ? (renamedBlock(entry) ?? entry) : entry,
      )
    : value;

/** A parsed config object with the 0.15 block names. */
export function renameBlocksInConfig(
  config: Record<string, unknown>,
): Record<string, unknown> {
  const out: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(config)) {
    if (key === "blocks") {
      out[key] = Array.isArray(value)
        ? renameList(value)
        : renameKeys(value, (name) => renamedBlock(name) ?? name);
    } else if (key === "preset" && isObject(value)) {
      out[key] =
        value["blocks"] === undefined
          ? value
          : { ...value, blocks: renameList(value["blocks"]) };
    } else if (key === "auth" && isObject(value)) {
      const authorization = value["authorization"];

      out[key] = isObject(authorization)
        ? {
            ...value,
            authorization:
              authorization["operations"] === undefined
                ? authorization
                : {
                    ...authorization,
                    operations: renameKeys(
                      authorization["operations"],
                      currentOperationName,
                    ),
                  },
          }
        : value;
    } else if (
      (key === "$env" && isObject(value)) ||
      (ENVIRONMENT_KEY.test(key) && isObject(value))
    ) {
      out[key] =
        key === "$env"
          ? Object.fromEntries(
              Object.entries(value).map(([name, entry]) => [
                name,
                isObject(entry) ? renameBlocksInConfig(entry) : entry,
              ]),
            )
          : renameBlocksInConfig(value);
    } else {
      out[key] = value;
    }
  }

  return out;
}

/** `edit`, then the 0.15 block names on its text. */
export function withBlockNames(edit: ConfigEdit, json: boolean): ConfigEdit {
  if (!edit.ok) {
    return edit;
  }

  if (!json) {
    return renameBlocksInSource(edit.text);
  }

  const config: unknown = JSON.parse(edit.text);

  if (!isObject(config)) {
    return edit;
  }

  const renamed = renameBlocksInConfig(config);

  return JSON.stringify(renamed) === JSON.stringify(config)
    ? edit
    : { ok: true, text: `${JSON.stringify(renamed, null, 2)}\n` };
}
