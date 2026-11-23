/**
 * Adds, sets and removes block entries in `better-supabase.config.ts`,
 * `better-supabase.config.json` and `lib/blocks.ts`. The TypeScript edits go
 * through a `ConfigDocument` (ADR 1186): it reads the object literal passed to
 * `defineConfig(...)` (or the default export) from a syntax tree, so strings
 * and comments never count as code, and writes the names in the form the config
 * already uses: `name: {}` in an object, `"name"` in a list. Anything that
 * isn't a literal it can follow is refused with a reason, and `add` prints the
 * snippet instead.
 */

import { walk } from "oxc-walker";

import type { PresetSpec } from "../../preset/index.ts";

import { ConfigDocument } from "../config-document/index.ts";
import { CliError } from "../core/errors.ts";
import { isRecord } from "../guards.ts";

export type ConfigEdit =
  | {
      readonly ok: true;
      readonly text: string;
      /** A part of the edit that was left out, and why. */
      readonly note?: string;
    }
  | { readonly ok: false; readonly reason: string };

const IDENT = /^[A-Za-z_$][\w$]*$/;

const NO_OBJECT = "it doesn't pass an object literal to defineConfig()";

/** A module name as an object key, quoted when it isn't an identifier. */
export const keyText = (name: string): string =>
  IDENT.test(name) ? name : `"${name}"`;

/**
 * The `blocks` list element for instance `name`: its quoted name when the entry
 * has no config, else `{ block, name?, ...entry }`.
 */
function listEntry(
  name: string,
  value: object,
  indent: string,
  quote: string,
): string {
  const { block: given, ...rest }: { block?: unknown } = value;
  const block = typeof given === "string" ? given : name;

  if (block === name && Object.keys(rest).length === 0) {
    return literal(name, indent, quote);
  }

  return literal(
    { block, ...(block === name ? {} : { name }), ...rest },
    indent,
    quote,
  );
}

/** `value` as a TypeScript literal, one key per line, indented from `indent`. */
function literal(value: unknown, indent: string, quote: string): string {
  if (value === null) {
    return "null";
  }

  if (typeof value === "string") {
    return value.includes(quote) || value.includes("\\")
      ? JSON.stringify(value)
      : `${quote}${value}${quote}`;
  }

  if (typeof value !== "object") {
    return String(value);
  }

  if (Array.isArray(value)) {
    return `[${value.map((item: unknown) => literal(item, indent, quote)).join(", ")}]`;
  }

  const entries = Object.entries(value);

  if (entries.length === 0) {
    return "{}";
  }

  const inner = `${indent}  `;

  return `{\n${entries.map(([key, entry]) => `${inner}${keyText(key)}: ${literal(entry, inner, quote)},`).join("\n")}\n${indent}}`;
}

/** `addBlocksToConfig` for `better-supabase.config.json`. */
export function addBlocksToJson(
  source: string,
  names: readonly string[],
): ConfigEdit {
  let config: unknown;

  try {
    config = JSON.parse(source);
  } catch {
    return { ok: false, reason: "it isn't valid JSON" };
  }

  if (!isRecord(config)) {
    return { ok: false, reason: "it isn't a JSON object" };
  }

  const blocks: unknown = config["blocks"] ?? [];
  let next: unknown;

  if (Array.isArray(blocks)) {
    const listed: readonly unknown[] = blocks;
    const present = new Set(listed.map(jsonListName));
    next = [...listed, ...names.filter((name) => !present.has(name))];
  } else if (isRecord(blocks)) {
    next = {
      ...blocks,
      ...Object.fromEntries(
        names.filter((name) => !(name in blocks)).map((name) => [name, {}]),
      ),
    };
  } else {
    return { ok: false, reason: "its blocks key isn't an object or a list" };
  }

  const indent = /^[ \t]+/m.exec(source)?.[0] ?? "  ";

  return jsonEdit(source, config, { ...config, blocks: next }, indent);
}

/**
 * The JSON config with `next` written, or `source` as it is when `next` holds
 * the same values, so a formatted file isn't rewritten for nothing.
 */
const jsonEdit = (
  source: string,
  config: unknown,
  next: unknown,
  indent: string,
): ConfigEdit => ({
  ok: true,
  text:
    JSON.stringify(next) === JSON.stringify(config)
      ? source
      : `${JSON.stringify(next, null, indent)}\n`,
});

/** `setPresetInConfig` for `better-supabase.config.json`. */
export function setPresetInJson(
  source: string,
  value: string | PresetSpec,
): ConfigEdit {
  let config: unknown;

  try {
    config = JSON.parse(source);
  } catch {
    return { ok: false, reason: "it isn't valid JSON" };
  }

  if (!isRecord(config)) {
    return { ok: false, reason: "it isn't a JSON object" };
  }

  const indent = /^[ \t]+/m.exec(source)?.[0] ?? "  ";

  return jsonEdit(source, config, { ...config, preset: value }, indent);
}

/** `setBlockInConfig` for `better-supabase.config.json`. */
export function setBlockInJson(
  source: string,
  name: string,
  value: object,
): ConfigEdit {
  let config: unknown;

  try {
    config = JSON.parse(source);
  } catch {
    return { ok: false, reason: "it isn't valid JSON" };
  }

  if (!isRecord(config)) {
    return { ok: false, reason: "it isn't a JSON object" };
  }

  const blocks: unknown = config["blocks"] ?? [];

  if (isRecord(blocks)) {
    return {
      ok: false,
      reason:
        "its blocks key is the object form. Run `better-supabase codemod blocks-list`",
    };
  }

  if (!Array.isArray(blocks)) {
    return { ok: false, reason: "its blocks key isn't a list" };
  }

  const indent = /^[ \t]+/m.exec(source)?.[0] ?? "  ";

  return jsonEdit(
    source,
    config,
    { ...config, blocks: withListEntry(blocks, name, value) },
    indent,
  );
}

/** The instance name of a JSON `blocks` list element. */
function jsonListName(item: unknown): string | undefined {
  if (typeof item === "string") {
    return item;
  }

  if (isRecord(item)) {
    const name = item["name"] ?? item["block"];

    return typeof name === "string" ? name : undefined;
  }

  return undefined;
}

/** The JSON list entry for instance `name`, like `listEntry`. */
function jsonListEntry(name: string, value: object): unknown {
  const { block: given, ...rest }: { block?: unknown } = value;
  const block = typeof given === "string" ? given : name;

  return block === name && Object.keys(rest).length === 0
    ? name
    : { block, ...(block === name ? {} : { name }), ...rest };
}

/** `list` with the entry for `name` replaced, or appended. */
function withListEntry(
  list: readonly unknown[],
  name: string,
  value: object,
): readonly unknown[] {
  const entry = jsonListEntry(name, value);
  const index = list.findIndex((item) => jsonListName(item) === name);

  return index === -1
    ? [...list, entry]
    : list.map((item, at) => (at === index ? entry : item));
}

/**
 * `value` under `path`, as nested objects: `["a", "b"]` and 1 give `{ a: { b: 1
 * } }`.
 */
const nested = (path: readonly string[], value: unknown): unknown =>
  path.reduceRight<unknown>((inner, key) => ({ [key]: inner }), value);

/** `value` in `object` at `path`, with the objects on the way copied. */
function withPath(
  object: Readonly<Record<string, unknown>>,
  path: readonly string[],
  value: unknown,
): Readonly<Record<string, unknown>> {
  const [key, ...rest] = path;

  if (key === undefined) {
    return object;
  }

  if (rest.length === 0) {
    return { ...object, [key]: value };
  }

  const inner: unknown = object[key];

  if (Array.isArray(inner)) {
    const [name, ...inside] = rest;
    const list: readonly unknown[] = inner;

    if (name === undefined) {
      return object;
    }

    const found = list.find((item) => jsonListName(item) === name);

    const entry: Readonly<Record<string, unknown>> = isRecord(found)
      ? found
      : { block: name };

    const merged =
      inside.length > 0
        ? withPath(entry, inside, value)
        : isRecord(value)
          ? jsonListEntry(name, value)
          : value;

    const kept = list.some((item) => jsonListName(item) === name);

    return {
      ...object,
      [key]: kept
        ? list.map((item) => (jsonListName(item) === name ? merged : item))
        : [...list, merged],
    };
  }

  const next: Readonly<Record<string, unknown>> = isRecord(inner) ? inner : {};

  return { ...object, [key]: withPath(next, rest, value) };
}

/** `setPathInConfig` for `better-supabase.config.json`. */
export function setPathInJson(
  source: string,
  path: readonly [string, ...string[]],
  value: unknown,
): ConfigEdit {
  let config: unknown;

  try {
    config = JSON.parse(source);
  } catch {
    return { ok: false, reason: "it isn't valid JSON" };
  }

  if (!isRecord(config)) {
    return { ok: false, reason: "it isn't a JSON object" };
  }

  const indent = /^[ \t]+/m.exec(source)?.[0] ?? "  ";

  return jsonEdit(source, config, withPath(config, path, value), indent);
}

/** The document for `source`, or the reason the edit cannot start. */
export function openConfig(source: string): ConfigDocument | ConfigEdit {
  try {
    const document = ConfigDocument.parse(source);

    return document.configObject() === undefined
      ? { ok: false, reason: NO_OBJECT }
      : document;
  } catch (error) {
    if (error instanceof CliError) {
      return { ok: false, reason: error.message };
    }

    throw error;
  }
}

/** The finished edit: the text, or the first thing the document flagged. */
export function finish(document: ConfigDocument): ConfigEdit {
  const [first] = document.review;

  return first === undefined
    ? { ok: true, text: document.text }
    : { ok: false, reason: first };
}

/** The leading whitespace of the line that holds `offset`. */
const indentAt = (source: string, offset: number): string =>
  /^[ \t]*/.exec(source.slice(source.lastIndexOf("\n", offset - 1) + 1))?.[0] ??
  "";

/** Where the entry or the first sibling of `path`'s owner sits, for indentation. */
function indentFor(document: ConfigDocument, path: readonly string[]): string {
  const found = document.locate(path);

  if (found !== undefined) {
    return indentAt(document.text, found.entry.start);
  }

  const parent =
    path.length === 1 ? undefined : document.locate(path.slice(0, -1));

  const owner = parent?.value ?? document.configObject();

  if (owner?.type === "ArrayExpression") {
    const last = owner.elements.findLast((each) => each !== null);

    return last === undefined
      ? `${indentAt(document.text, owner.start)}${document.style.indent}`
      : indentAt(document.text, last.start);
  }

  const first =
    owner?.type === "ObjectExpression" ? owner.properties[0] : undefined;

  if (first !== undefined) {
    return indentAt(document.text, first.start);
  }

  return owner === undefined
    ? ""
    : `${indentAt(document.text, owner.start)}${document.style.indent}`;
}

/** `source` with `names` added to `blocks`, keeping the form it has. */
export function addBlocksToConfig(
  source: string,
  names: readonly string[],
): ConfigEdit {
  const document = openConfig(source);

  if (!(document instanceof ConfigDocument)) {
    return document;
  }

  const { quote } = document.style;
  const blocks = document.locate(["blocks"]);

  if (blocks === undefined) {
    document.set(
      ["blocks"],
      `[${names.map((name) => `${quote}${name}${quote}`).join(", ")}]`,
    );

    return finish(document);
  }

  if (blocks.value.type === "ObjectExpression") {
    for (const name of names) {
      if (!document.has(["blocks", name])) {
        document.set(["blocks", name], "{}");
      }
    }

    return finish(document);
  }

  if (blocks.value.type === "ArrayExpression") {
    const listed = document.text.slice(blocks.value.start, blocks.value.end);
    const used = /(["'])/.exec(listed)?.[1] ?? quote;

    for (const name of names) {
      if (!document.has(["blocks", name])) {
        document.append(["blocks"], `${used}${name}${used}`);
      }
    }

    return finish(document);
  }

  return { ok: false, reason: "its blocks key isn't a literal object or list" };
}

/**
 * `source` with `preset` set to `value` (a preset name or object), replacing
 * the one it has.
 */
export function setPresetInConfig(
  source: string,
  value: string | PresetSpec,
): ConfigEdit {
  const document = openConfig(source);

  if (!(document instanceof ConfigDocument)) {
    return document;
  }

  document.set(
    ["preset"],
    literal(value, indentFor(document, ["preset"]), document.style.quote),
  );

  return finish(document);
}

/** A block client to wire: `key: exportName`, imported from `subpath`. */
export interface WiredBlock {
  readonly key: string;
  readonly export: string;
  readonly subpath: string;
}

const NO_WIRING = "it doesn't call defineBlocks() or createBlocks()";

/** The wiring document, or the reason the edit cannot start. */
export function openWiring(source: string): ConfigDocument | ConfigEdit {
  try {
    const document = ConfigDocument.parseWiring(source);

    const call = document.wiredCall();

    if (call === undefined) {
      return { ok: false, reason: NO_WIRING };
    }

    return call.blocks === undefined
      ? {
          ok: false,
          reason: `${call.name}() isn't passed an object literal of blocks`,
        }
      : document;
  } catch (error) {
    if (error instanceof CliError) {
      return { ok: false, reason: error.message };
    }

    throw error;
  }
}

/** Every identifier the module names: declarations, imports and references. */
function identifiersIn(document: ConfigDocument): ReadonlySet<string> {
  const names = new Set<string>();

  document.rewrite(({ program }) => {
    walk(program, {
      enter(node) {
        if (node.type === "Identifier") {
          names.add(node.name);
        }
      },
    });
  });

  return names;
}

/**
 * `lib/blocks.ts` with `blocks` imported and added to the blocks object passed
 * to `defineBlocks(blockConfig, { ... })` or `createBlocks(options, { ... })`.
 * A block whose export the file already names is left out.
 */
export function addBlocksToWiring(
  source: string,
  blocks: readonly WiredBlock[],
): ConfigEdit {
  const document = openWiring(source);

  if (!(document instanceof ConfigDocument)) {
    return document;
  }

  const named = identifiersIn(document);
  const missing = blocks.filter((block) => !named.has(block.export));

  if (missing.length === 0) {
    return { ok: true, text: source };
  }

  for (const block of missing) {
    document.set([block.key], block.export);
  }

  const lines = missing
    .map((block) => `import { ${block.export} } from "${block.subpath}";`)
    .join("\n");

  document.rewrite(({ program, edit }) => {
    const last = program.body.findLast(
      (statement) => statement.type === "ImportDeclaration",
    );

    if (last === undefined) {
      edit.prepend(`${lines}\n\n`);
    } else {
      edit.appendLeft(last.end, `\n${lines}`);
    }
  });

  return finish(document);
}

/**
 * `source` with the `blocks` entry for instance `name` set to `value`,
 * replacing the entry it has: a name in the list, or a `{ block, name?, ... }`
 * object.
 */
export function setBlockInConfig(
  source: string,
  name: string,
  value: object,
): ConfigEdit {
  const document = openConfig(source);

  if (!(document instanceof ConfigDocument)) {
    return document;
  }

  const { quote } = document.style;
  const blocks = document.locate(["blocks"]);

  if (blocks === undefined) {
    document.set(
      ["blocks"],
      `[${listEntry(name, value, indentFor(document, ["blocks"]), quote)}]`,
    );

    return finish(document);
  }

  if (blocks.value.type === "ObjectExpression") {
    const current = document.locate(["blocks", name]);

    if (
      current?.entry.type === "Property" &&
      (current.entry.method || current.entry.kind !== "init")
    ) {
      return { ok: false, reason: `blocks.${name} is a method, not a value` };
    }

    document.set(
      ["blocks", name],
      literal(value, indentFor(document, ["blocks", name]), quote),
    );

    return finish(document);
  }

  if (blocks.value.type === "ArrayExpression") {
    const indent = indentFor(document, ["blocks", name]);
    const entry = listEntry(name, value, indent, quote);

    if (document.has(["blocks", name])) {
      document.set(["blocks", name], entry);
    } else {
      document.append(["blocks"], entry);
    }

    return finish(document);
  }

  return { ok: false, reason: "its blocks key isn't a literal object or list" };
}

/**
 * `source` with the key at `path` set to `value`, replacing what it has and
 * creating the objects on the way: `["tables", "projects"]` sets one app table
 * and keeps the others. An entry of a `blocks` list keeps its own keys.
 */
export function setPathInConfig(
  source: string,
  path: readonly [string, ...string[]],
  value: unknown,
): ConfigEdit {
  const document = openConfig(source);

  if (!(document instanceof ConfigDocument)) {
    return document;
  }

  const { quote } = document.style;

  const blocksList =
    path[0] === "blocks" &&
    document.locate(["blocks"])?.value.type === "ArrayExpression";

  for (let index = 0; index < path.length; index += 1) {
    const prefix = path.slice(0, index + 1);
    const rest = path.slice(index + 1);
    const found = document.locate(prefix);
    const at = prefix.join(".");

    if (blocksList && index === 1) {
      const block = path[1]!;

      // The element is the instance's own object: keep its keys and continue
      // inside it. Otherwise the element is replaced or added as a whole.
      if (found?.value.type === "ObjectExpression" && rest.length > 0) {
        continue;
      }

      const entry = listEntry(
        block,
        nested(rest, value) ?? {},
        indentFor(document, prefix),
        quote,
      );

      if (found === undefined) {
        document.append(["blocks"], entry);
      } else {
        document.set(prefix, entry);
      }

      return finish(document);
    }

    if (found === undefined) {
      document.set(
        prefix,
        literal(nested(rest, value), indentFor(document, prefix), quote),
      );

      return finish(document);
    }

    if (rest.length === 0) {
      document.set(prefix, literal(value, indentFor(document, prefix), quote));

      return finish(document);
    }

    if (blocksList && index === 0) {
      continue;
    }

    if (found.value.type !== "ObjectExpression") {
      return { ok: false, reason: `its ${at} key isn't a literal object` };
    }
  }

  return { ok: false, reason: "the path is empty" };
}
