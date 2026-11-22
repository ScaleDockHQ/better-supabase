import {
  applyEdits,
  findNodeAtLocation,
  modify,
  parse as parseJsonc,
  parseTree,
} from "jsonc-parser";
import { existsSync, readdirSync } from "node:fs";
import { glob, readFile } from "node:fs/promises";
import { dirname, join, posix, relative } from "node:path";
import { parse } from "smol-toml";

import type { SqlWorkflow } from "../config/index.ts";

export type TomlValue =
  | string
  | number
  | boolean
  | readonly TomlValue[]
  | TomlTable;

export interface TomlTable {
  readonly [key: string]: TomlValue;
}

/** The formats the Supabase CLI reads its project config from. */
export type ConfigFormat = "toml" | "json" | "jsonc";

/** A key or table in the config file, 1-based. */
export interface ConfigLocation {
  readonly line: number;
  readonly column: number;
  /** False when only an enclosing table or object holds the key. */
  readonly exact: boolean;
}

/**
 * The Supabase project config, parsed from `config.toml`, `config.json` or
 * `config.jsonc` (the name `SupabaseToml` had before CLI 3.2.0 read all
 * three).
 */
export interface SupabaseConfig {
  /**
   * Relative to the project root (`../../supabase/config.toml` in a monorepo
   * package).
   */
  readonly path: string;
  /** The `supabase` directory, relative to the project root. */
  readonly dir: string;
  readonly format: ConfigFormat;
  readonly text: string;
  /**
   * The keys present in the file (snake_case, as written), after `env()`
   * interpolation when parsed by `@supabase/config`.
   */
  readonly document: TomlTable;
  readonly parser: "@supabase/config" | "jsonc-parser" | "smol-toml";
  /** Where `keyPath` (`['auth', 'jwt_expiry']`) sits in the file. */
  locate(keyPath: readonly string[]): ConfigLocation | undefined;
  /** The value at `keyPath` as written, before `env()` interpolation. */
  raw(keyPath: readonly string[]): TomlValue | undefined;
}

/** The file names the CLI looks for in `supabase/`, in its order of preference. */
const CONFIG_FILES: readonly {
  readonly name: string;
  readonly format: ConfigFormat;
}[] = [
  { name: "config.json", format: "json" },
  { name: "config.jsonc", format: "jsonc" },
  { name: "config.toml", format: "toml" },
];

/**
 * The config file in `dir` (a `supabase` folder, or a stack folder under
 * `supabase/stacks`), by the CLI's order of preference.
 */
export function configFileInDir(
  dir: string,
): { readonly name: string; readonly format: ConfigFormat } | undefined {
  return CONFIG_FILES.find(({ name }) => existsSync(join(dir, name)));
}

/** The config file in `<root>/supabase`, by the CLI's order of preference. */
export function configFileIn(
  root: string,
): { readonly name: string; readonly format: ConfigFormat } | undefined {
  return configFileInDir(join(root, "supabase"));
}

/**
 * The config of one folder (such as `supabase/stacks/<name>`), parsed without
 * `env()` interpolation; undefined without a config file there.
 */
export async function readConfigInDir(
  dir: string,
): Promise<SupabaseConfig | undefined> {
  const file = configFileInDir(dir);

  if (file === undefined) {
    return undefined;
  }

  return supabaseConfigFromText(
    await readFile(join(dir, file.name), "utf-8"),
    join(dir, file.name),
  );
}

/** Both `config.json` and `config.jsonc` exist, which the CLI refuses. */
export function configFileConflict(root: string): boolean {
  return (
    existsSync(join(root, "supabase", "config.json")) &&
    existsSync(join(root, "supabase", "config.jsonc"))
  );
}

/**
 * The nearest directory at or above `start` where `found` is true. The search
 * stops after the first directory with `.git`, so a checkout never picks up a
 * project outside it.
 */
export function findUp(
  start: string,
  found: (dir: string) => boolean,
): string | undefined {
  let dir = start;

  for (;;) {
    if (found(dir)) {
      return dir;
    }

    const parent = dirname(dir);

    if (parent === dir || existsSync(join(dir, ".git"))) {
      return undefined;
    }

    dir = parent;
  }
}

/**
 * The nearest directory at or above `start` that has `supabase/config.toml`,
 * `config.json` or `config.jsonc`, like the Supabase CLI's search, within the
 * same `.git` boundary.
 */
export function findSupabaseRoot(start: string): string | undefined {
  return findUp(start, (dir) => configFileIn(dir) !== undefined);
}

/**
 * The repository root for `start`: the directory with `.git`, else the Supabase
 * project root, else `start`.
 */
export function findRepoRoot(start: string): string {
  let dir = start;

  for (;;) {
    if (existsSync(join(dir, ".git"))) {
      return dir;
    }

    const parent = dirname(dir);

    if (parent === dir) {
      return findSupabaseRoot(start) ?? start;
    }

    dir = parent;
  }
}

/**
 * The `supabase` directory relative to `root`: the one `findSupabaseRoot`
 * finds, or `supabase`.
 */
export function supabaseDir(root: string): string {
  const found = findSupabaseRoot(root);

  return found === undefined
    ? "supabase"
    : relativePath(root, join(found, "supabase"));
}

/** `path` under `from`, with forward slashes. */
function relativePath(from: string, path: string): string {
  return relative(from, path).replaceAll("\\", "/") || ".";
}

interface SupabaseConfigIo {
  loadCliConfig(
    cwd: string,
    options: { readonly tomlOnly: boolean; readonly search: boolean },
  ): Promise<{ readonly document?: Record<string, unknown> } | null>;
}

/**
 * `@supabase/config` is an optional peer (it needs `effect` and
 * `@effect/platform-node`), so it is imported lazily through a variable:
 * projects without it get smol-toml instead of a load error.
 */
async function loadSupabaseConfig(): Promise<SupabaseConfigIo | undefined> {
  const specifier = "@supabase/config/io";

  try {
    // SAFETY: @supabase/config/io exports this interface; the catch falls back
    // when it is missing.
    return (await import(specifier)) as SupabaseConfigIo;
  } catch {
    return undefined;
  }
}

function toTomlValue(value: unknown): TomlValue {
  if (Array.isArray(value)) {
    return value.map(toTomlValue);
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  if (typeof value === "bigint") {
    return Number(value);
  }

  if (typeof value === "object" && value !== null) {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, toTomlValue(item)]),
    );
  }

  if (
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "boolean"
  ) {
    return value;
  }

  return String(value);
}

/**
 * `text` as TOML, with dates as ISO strings; an empty table when it does not
 * parse.
 */
export function parseToml(text: string): TomlTable {
  try {
    return Object.fromEntries(
      Object.entries(parse(text)).map(([key, value]) => [
        key,
        toTomlValue(value),
      ]),
    );
  } catch {
    return {};
  }
}

/**
 * `text` as a JSON document with comments and trailing commas; an empty table
 * when it does not parse.
 */
function parseJsonConfig(text: string): TomlTable {
  const value: unknown = parseJsonc(text, [], { allowTrailingComma: true });

  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? toTomlTable(value)
    : {};
}

function toTomlTable(value: object): TomlTable {
  return Object.fromEntries(
    Object.entries(value).map(([key, item]) => [key, toTomlValue(item)]),
  );
}

function parseText(text: string, format: ConfigFormat): TomlTable {
  return format === "toml" ? parseToml(text) : parseJsonConfig(text);
}

/** Splits a dotted TOML key (`a."b.c".d`) into its parts. */
function splitTomlKey(key: string): string[] {
  const parts: string[] = [];

  const pattern =
    /\s*(?:"((?:[^"\\]|\\.)*)"|'([^']*)'|([A-Za-z0-9_-]+))\s*(?:\.|$)/y;

  for (;;) {
    const match = pattern.exec(key);

    if (match === null || match[0] === "") {
      return parts;
    }

    parts.push(match[1] ?? match[2] ?? match[3] ?? "");

    if (pattern.lastIndex >= key.length) {
      return parts;
    }
  }
}

const sameKeys = (a: readonly string[], b: readonly string[]): boolean =>
  a.length === b.length && a.every((key, index) => key === b[index]);

interface TomlEntry {
  readonly kind: "table" | "key";
  readonly path: readonly string[];
  readonly line: number;
  readonly column: number;
}

/** The tables and keys of a TOML file with their full paths and positions. */
function tomlEntries(text: string): TomlEntry[] {
  const entries: TomlEntry[] = [];
  let table: string[] = [];

  for (const [index, line] of text.split(/\r?\n/).entries()) {
    const header = /^(\s*)\[\[?\s*([^\]]+?)\s*\]\]?\s*(?:#.*)?$/.exec(line);

    if (header !== null) {
      table = splitTomlKey(header[2] ?? "");
      entries.push({
        kind: "table",
        path: table,
        line: index + 1,
        column: (header[1]?.length ?? 0) + 1,
      });
      continue;
    }

    const key =
      /^(\s*)((?:"[^"]*"|'[^']*'|[A-Za-z0-9_-]+)(?:\s*\.\s*(?:"[^"]*"|'[^']*'|[A-Za-z0-9_-]+))*)\s*=/.exec(
        line,
      );

    if (key !== null) {
      entries.push({
        kind: "key",
        path: [...table, ...splitTomlKey(key[2] ?? "")],
        line: index + 1,
        column: (key[1]?.length ?? 0) + 1,
      });
    }
  }

  return entries;
}

function locateToml(
  text: string,
  keyPath: readonly string[],
): ConfigLocation | undefined {
  const entries = tomlEntries(text);

  const exact =
    entries.find(
      (entry) => entry.kind === "key" && sameKeys(entry.path, keyPath),
    ) ?? entries.find((entry) => sameKeys(entry.path, keyPath));

  if (exact !== undefined) {
    return { line: exact.line, column: exact.column, exact: true };
  }

  for (let length = keyPath.length - 1; length > 0; length -= 1) {
    const table = entries.find(
      (entry) =>
        entry.kind === "table" &&
        sameKeys(entry.path, keyPath.slice(0, length)),
    );

    if (table !== undefined) {
      return { line: table.line, column: table.column, exact: false };
    }
  }

  return undefined;
}

function positionAt(text: string, offset: number): ConfigLocation {
  const before = text.slice(0, offset);
  const line = before.split("\n").length;

  return {
    line,
    column: offset - (before.lastIndexOf("\n") + 1) + 1,
    exact: true,
  };
}

function locateJson(
  text: string,
  keyPath: readonly string[],
): ConfigLocation | undefined {
  const tree = parseTree(text, [], { allowTrailingComma: true });

  if (tree === undefined) {
    return undefined;
  }

  for (let length = keyPath.length; length > 0; length -= 1) {
    const node = findNodeAtLocation(tree, [...keyPath.slice(0, length)]);
    const property = node?.parent?.type === "property" ? node.parent : node;

    if (property !== undefined) {
      return {
        ...positionAt(text, property.offset),
        exact: length === keyPath.length,
      };
    }
  }

  return undefined;
}

/** The value at `keyPath` in `document`, with `unknown` for anything absent. */
function valueAt(
  document: TomlTable,
  keyPath: readonly string[],
): TomlValue | undefined {
  let value: TomlValue | undefined = document;

  for (const key of keyPath) {
    if (typeof value !== "object" || Array.isArray(value)) {
      return undefined;
    }

    // SAFETY: the check above narrows value to a table.
    value = (value as TomlTable)[key];
  }

  return value;
}

/** A config from its parts, for code that already holds the document. */
export function makeSupabaseConfig(parts: {
  readonly path: string;
  readonly dir: string;
  readonly format: ConfigFormat;
  readonly text: string;
  readonly document: TomlTable;
  readonly parser: SupabaseConfig["parser"];
}): SupabaseConfig {
  const { format, text } = parts;
  let rawDocument: TomlTable | undefined;

  return {
    ...parts,
    locate: (keyPath) =>
      format === "toml" ? locateToml(text, keyPath) : locateJson(text, keyPath),
    raw: (keyPath) => {
      rawDocument ??= parseText(text, format);

      return valueAt(rawDocument, keyPath);
    },
  };
}

/**
 * A config from its text, parsed without `@supabase/config` (so `env()` values
 * stay as written). `file` is `config.toml`, `config.json` or `config.jsonc`;
 * the format follows its extension.
 */
export function supabaseConfigFromText(
  text: string,
  file = "supabase/config.toml",
): SupabaseConfig {
  const format: ConfigFormat = file.endsWith(".toml")
    ? "toml"
    : file.endsWith(".jsonc")
      ? "jsonc"
      : "json";

  return makeSupabaseConfig({
    path: file,
    dir: posix.dirname(file),
    format,
    text,
    document: parseText(text, format),
    parser: format === "toml" ? "smol-toml" : "jsonc-parser",
  });
}

const parsed = new Map<
  string,
  { readonly text: string; readonly config: Promise<SupabaseConfig> }
>();

/**
 * Reads the project config (`config.json`, `config.jsonc` or `config.toml`, the
 * order the CLI prefers) from `root` or the nearest parent that has one
 * (`findSupabaseRoot`). A file with `env()` values goes through
 * `@supabase/config` when it is installed, which resolves them; any other file,
 * or a project without it, is parsed directly (smol-toml, jsonc-parser), since
 * loading `@supabase/config` costs hundreds of milliseconds. Parses are reused
 * while the file's text is unchanged.
 */
export async function readSupabaseConfig(
  root: string,
): Promise<SupabaseConfig | undefined> {
  const found = findSupabaseRoot(root);

  if (found === undefined) {
    return undefined;
  }

  const file = configFileIn(found);

  if (file === undefined) {
    return undefined;
  }

  const absolute = join(found, "supabase", file.name);
  const text = await readFile(absolute, "utf-8");
  const key = `${root}\0${absolute}`;
  const cached = parsed.get(key);

  if (cached?.text === text) {
    return cached.config;
  }

  const config = parseSupabaseConfig(found, text, file.format, {
    path: relativePath(root, absolute),
    dir: relativePath(root, join(found, "supabase")),
  });

  parsed.set(key, { text, config });

  return config;
}

async function parseSupabaseConfig(
  found: string,
  text: string,
  format: ConfigFormat,
  location: { readonly path: string; readonly dir: string },
): Promise<SupabaseConfig> {
  const io = text.includes("env(") ? await loadSupabaseConfig() : undefined;

  if (io) {
    try {
      const loaded = await io.loadCliConfig(found, {
        tomlOnly: format === "toml",
        search: false,
      });

      if (loaded?.document) {
        return makeSupabaseConfig({
          ...location,
          format,
          text,
          // SAFETY: @supabase/config parses the config into plain values.
          document: loaded.document as TomlTable,
          parser: "@supabase/config",
        });
      }
    } catch {
      // An invalid file for @supabase/config's schema still has readable keys.
    }
  }

  return makeSupabaseConfig({
    ...location,
    format,
    text,
    document: parseText(text, format),
    parser: format === "toml" ? "smol-toml" : "jsonc-parser",
  });
}

/** What `withConfigValue` writes: scalars and lists of strings. */
export type ConfigScalar = string | number | boolean | readonly string[];

function tomlValueText(value: ConfigScalar): string {
  return typeof value === "string" || Array.isArray(value)
    ? JSON.stringify(value)
    : String(value);
}

function withTomlValue(
  text: string,
  keyPath: readonly string[],
  value: ConfigScalar,
): string {
  const eol = text.includes("\r\n") ? "\r\n" : "\n";
  const lines = text.split(/\r?\n/);
  const entries = tomlEntries(text);
  const key = keyPath.at(-1) ?? "";
  const table = keyPath.slice(0, -1);
  const rendered = `${key} = ${tomlValueText(value)}`;

  const existing = entries.find(
    (entry) => entry.kind === "key" && sameKeys(entry.path, keyPath),
  );

  if (existing !== undefined) {
    const line = lines[existing.line - 1] ?? "";
    const indent = line.slice(0, existing.column - 1);
    const comment = /\s+#[^"']*$/.exec(line)?.[0] ?? "";

    lines[existing.line - 1] = `${indent}${rendered}${comment}`;

    return lines.join(eol);
  }

  const header = entries.find(
    (entry) => entry.kind === "table" && sameKeys(entry.path, table),
  );

  if (header === undefined) {
    const body = text === "" || text.endsWith("\n") ? text : `${text}${eol}`;
    const gap = body === "" || body.endsWith(`${eol}${eol}`) ? "" : eol;

    return `${body}${gap}[${table.join(".")}]${eol}${rendered}${eol}`;
  }

  const next = entries.find(
    (entry) => entry.kind === "table" && entry.line > header.line,
  );

  let at = (next?.line ?? lines.length + 1) - 1;

  while (at > header.line && (lines[at - 1] ?? "").trim() === "") {
    at -= 1;
  }

  lines.splice(at, 0, rendered);

  return lines.join(eol);
}

/**
 * `text` with the value at `keyPath` set, in the format of the file: the one
 * place that edits the project config. Comments and the other keys stay as they
 * are. The caller writes the result (through `applyPlan`).
 */
export function withConfigValue(
  config: Pick<SupabaseConfig, "format" | "text">,
  keyPath: readonly string[],
  value: ConfigScalar,
): string {
  if (config.format === "toml") {
    return withTomlValue(config.text, keyPath, value);
  }

  const eol = config.text.includes("\r\n") ? "\r\n" : "\n";

  return applyEdits(
    config.text,
    modify(config.text, [...keyPath], value, {
      formattingOptions: { insertSpaces: true, tabSize: 2, eol },
    }),
  );
}

/** The value at `path` (`['auth', 'jwt_expiry']`), if present. */
export function tomlGet(
  document: TomlTable,
  path: readonly string[],
): TomlValue | undefined {
  let value: TomlValue | undefined = document;

  for (const key of path) {
    if (typeof value !== "object" || Array.isArray(value)) {
      return undefined;
    }

    // SAFETY: the check above narrows value to a TOML table.
    value = (value as TomlTable)[key];
  }

  return value;
}

export function tomlNumber(
  document: TomlTable,
  path: readonly string[],
): number | undefined {
  const value = tomlGet(document, path);

  if (typeof value === "number") {
    return value;
  }

  if (
    typeof value === "string" &&
    value.trim() !== "" &&
    Number.isFinite(Number(value))
  ) {
    return Number(value);
  }

  return undefined;
}

/** An enabled `[auth.hook.<hook>]` backed by a Postgres function. */
export interface PgFunctionHook {
  readonly hook: string;
  readonly uri: string;
  readonly schema: string;
  readonly name: string;
}

/** `pg-functions://postgres/<schema>/<function>` as schema and name. */
function parsePgFunctionUri(
  uri: string,
): { readonly schema: string; readonly name: string } | undefined {
  const match = /^pg-functions:\/\/[^/]+\/([^/]+)\/([^/?#]+)$/.exec(uri.trim());

  return match ? { schema: match[1]!, name: match[2]! } : undefined;
}

/** The enabled Auth hooks with a `pg-functions://` URI, by hook name. */
export function pgFunctionHooks(document: TomlTable): PgFunctionHook[] {
  const hooks = tomlGet(document, ["auth", "hook"]);

  if (typeof hooks !== "object" || Array.isArray(hooks)) {
    return [];
  }

  // SAFETY: the check above narrows hooks to a TOML table.
  return Object.entries(hooks as TomlTable).flatMap(([hook, table]) => {
    if (typeof table !== "object" || Array.isArray(table)) {
      return [];
    }

    // SAFETY: the check above narrows table to a TOML table.
    const { enabled, uri } = table as TomlTable;

    if ((enabled !== true && enabled !== "true") || typeof uri !== "string") {
      return [];
    }

    const target = parsePgFunctionUri(uri);

    return target ? [{ hook, uri, ...target }] : [];
  });
}

/** An enabled `[auth.hook.<hook>]` that Auth calls over HTTP. */
export interface HttpHook {
  readonly hook: string;
  readonly uri: URL;
  /**
   * `secrets` as parsed: after `env()` interpolation when `@supabase/config`
   * read the file.
   */
  readonly secrets: string | undefined;
}

/** The enabled Auth hooks with an `http://` or `https://` URI, by hook name. */
export function httpHooks(document: TomlTable): HttpHook[] {
  const hooks = tomlGet(document, ["auth", "hook"]);

  if (typeof hooks !== "object" || Array.isArray(hooks)) {
    return [];
  }

  // SAFETY: the check above narrows hooks to a TOML table.
  return Object.entries(hooks as TomlTable).flatMap(([hook, table]) => {
    if (typeof table !== "object" || Array.isArray(table)) {
      return [];
    }

    // SAFETY: the check above narrows table to a TOML table.
    const { enabled, uri, secrets } = table as TomlTable;

    if ((enabled !== true && enabled !== "true") || typeof uri !== "string") {
      return [];
    }

    if (!/^https?:\/\//i.test(uri.trim()) || !URL.canParse(uri.trim())) {
      return [];
    }

    return [
      {
        hook,
        uri: new URL(uri.trim()),
        secrets: typeof secrets === "string" ? secrets : undefined,
      },
    ];
  });
}

/** The Supabase CLI engine that turns `supabase/schemas` into migrations. */
export type DiffEngine = "pg-delta" | "migra";

/**
 * The engine the Supabase CLI runs: pg-delta when `[experimental.pgdelta]
 * enabled = true`, otherwise the legacy migra engine.
 */
export function diffEngine(toml?: SupabaseConfig): DiffEngine {
  const enabled = tomlGet(toml?.document ?? {}, [
    "experimental",
    "pgdelta",
    "enabled",
  ]);

  return enabled === true || enabled === "true" ? "pg-delta" : "migra";
}

/** Whether `dir` (or a folder below it) holds a `.sql` file. */
function hasSqlFiles(dir: string): boolean {
  if (!existsSync(dir)) {
    return false;
  }

  try {
    return readdirSync(dir, { recursive: true }).some((name) =>
      String(name).endsWith(".sql"),
    );
  } catch {
    return false;
  }
}

/**
 * The workflow a project without `sql.workflow` follows: pg-delta when
 * `config.toml` enables it, migra when it turns pg-delta off (`enabled =
 * false`), lists `[db.migrations] schema_paths` or already keeps files in
 * `supabase/schemas` without pg-delta, and pg-delta otherwise. `schemaFiles`
 * says whether that folder holds SQL files when the caller already read it.
 */
export function detectWorkflow(
  root: string,
  toml?: SupabaseConfig,
  schemaFiles?: boolean,
): Exclude<SqlWorkflow, "migrations"> {
  if (diffEngine(toml) === "pg-delta" || toml === undefined) {
    return "pg-delta";
  }

  if (
    tomlGet(toml.document, ["experimental", "pgdelta", "enabled"]) !== undefined
  ) {
    return "migra";
  }

  const paths = tomlGet(toml.document, ["db", "migrations", "schema_paths"]);

  if (Array.isArray(paths) && paths.length > 0) {
    return "migra";
  }

  return (schemaFiles ?? hasSqlFiles(join(root, toml.dir, "schemas")))
    ? "migra"
    : "pg-delta";
}

/** `sql.workflow`, or the one `detectWorkflow` reads from `config.toml`. */
export function sqlWorkflow(
  config: {
    readonly root: string;
    readonly sql: { readonly workflow?: SqlWorkflow | undefined };
  },
  toml?: SupabaseConfig,
): SqlWorkflow {
  return config.sql.workflow ?? detectWorkflow(config.root, toml);
}

/**
 * The command that turns the files into a migration (named `name`, when given).
 * Under the migrations workflow the `sql` commands already wrote it, so the
 * command applies it.
 */
export function migrationCommand(workflow: SqlWorkflow, name?: string): string {
  switch (workflow) {
    case "pg-delta": {
      return name === undefined
        ? "supabase db schema declarative sync"
        : `supabase db schema declarative sync -f ${name}`;
    }

    case "migra": {
      return name === undefined
        ? "supabase db diff"
        : `supabase db diff -f ${name}`;
    }

    case "migrations": {
      return "supabase migration up";
    }

    default: {
      const unreachable: never = workflow;

      return unreachable;
    }
  }
}

/** The declarative schema files, in the order the diff engine reads them. */
export interface SchemaPaths {
  /** Relative to the project root. */
  readonly files: readonly string[];
  /**
   * Files under `supabase/schemas` that no `schema_paths` entry matches, so the
   * diff skips them.
   */
  readonly unlisted: readonly string[];
  /**
   * Whether `[db.migrations] schema_paths` lists entries that the engine honors
   * (migra only).
   */
  readonly configured: boolean;
}

/**
 * `experimental.pgdelta.declarative_schema_path` (relative to `supabase/`), or
 * `./schemas`.
 */
function pgDeltaSchemasDir(toml?: SupabaseConfig): string {
  const dir = tomlGet(toml?.document ?? {}, [
    "experimental",
    "pgdelta",
    "declarative_schema_path",
  ]);

  const schemas =
    typeof dir === "string" && dir.trim() !== "" ? dir : "schemas";

  return posix.join(
    toml?.dir ?? "supabase",
    schemas.replace(/^\.\//, "").replace(/\/$/, ""),
  );
}

/**
 * The folder the diff engine loads declarative schema files from, relative to
 * the root: `declarative_schema_path` under pg-delta, `supabase/schemas`
 * otherwise. `workflow` defaults to what `config.toml` turns on.
 */
export function declarativeSchemasDir(
  toml?: SupabaseConfig,
  workflow: SqlWorkflow = diffEngine(toml),
): string {
  return workflow === "pg-delta"
    ? pgDeltaSchemasDir(toml)
    : posix.join(toml?.dir ?? "supabase", "schemas");
}

async function expand(cwd: string, pattern: string): Promise<string[]> {
  const matched: string[] = [];

  for await (const path of glob(pattern.replace(/^\.\//, ""), { cwd })) {
    if (path.endsWith(".sql")) {
      matched.push(path.replaceAll("\\", "/"));
    }
  }

  return matched.toSorted();
}

/**
 * `[db.migrations] schema_paths` (relative to `supabase/`) with each glob
 * expanded in name order and the entries kept in their listed order, then the
 * `supabase/schemas` files no entry matches. Without `schema_paths`, the
 * `supabase/schemas` files in name order, as the Supabase CLI reads them.
 * pg-delta ignores `schema_paths` and orders by dependency, so under it every
 * file in its schema directory counts, in name order. The migrations workflow
 * has no declarative schemas. `workflow` defaults to `detectWorkflow`.
 */
export async function schemaPaths(
  root: string,
  toml?: SupabaseConfig,
  workflow: SqlWorkflow = detectWorkflow(root, toml),
): Promise<SchemaPaths> {
  if (workflow === "migrations") {
    return { files: [], unlisted: [], configured: false };
  }

  if (workflow === "pg-delta") {
    const dir = pgDeltaSchemasDir(toml);

    const files = existsSync(join(root, dir))
      ? await expand(root, `${dir}/**/*.sql`)
      : [];

    return { files, unlisted: [], configured: false };
  }

  const dir = toml?.dir ?? "supabase";
  const supabase = join(root, dir);

  const all = existsSync(join(supabase, "schemas"))
    ? (await expand(supabase, "schemas/**/*.sql")).map((path) =>
        posix.join(dir, path),
      )
    : [];

  const entries = tomlGet(toml?.document ?? {}, [
    "db",
    "migrations",
    "schema_paths",
  ]);

  const patterns = Array.isArray(entries)
    ? entries.filter((entry): entry is string => typeof entry === "string")
    : [];

  if (patterns.length === 0) {
    return { files: all, unlisted: [], configured: false };
  }

  const listed = new Set<string>();

  for (const pattern of patterns) {
    for (const path of await expand(supabase, pattern)) {
      listed.add(posix.join(dir, path));
    }
  }

  const unlisted = all.filter((path) => !listed.has(path));

  return { files: [...listed, ...unlisted], unlisted, configured: true };
}
