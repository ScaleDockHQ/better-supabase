import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { AccessBlockConfig, BlockConfig } from "../config/blocks.ts";
import type {
  AppTableConfig,
  AppTablesConfig,
} from "../config/types/app-tables.ts";
import type { PresetCatalog } from "./catalog-types.ts";
import type { Preset } from "./fields.ts";
import type { ResolvedPreset } from "./resolve.ts";

import { appTablesOf } from "../config/app-tables.ts";
import { PRESET_CATALOG } from "./catalog.generated.ts";
import { encodePreset } from "./code.ts";
import { presetConfig, presetOf } from "./config.ts";
import {
  type ConfigSourceKeys,
  configSource,
  createUrl,
  presetApplyCommand,
  presetInstallCommand,
} from "./render.ts";

/**
 * What the `/create` canvas adds to a preset (ADR 0040): tables the app
 * owns, extra columns on block tables, and where each table sits on the
 * canvas. It travels in the `&design=` parameter of a `/create` URL.
 */
export interface CreateDesign {
  /** `config.appTables`. */
  readonly appTables?: Readonly<Record<string, AppTableConfig>>;
  /** `blocks.<module>.options.extraColumns`: column name to SQL type, per module. */
  readonly extraColumns?: Readonly<
    Record<string, Readonly<Record<string, string>>>
  >;
  /** Canvas positions by `schema.table`, as `[x, y]`; the config ignores them. */
  readonly positions?: Readonly<Record<string, readonly [number, number]>>;
}

/**
 * The first character of a design code: how it is encoded. `0` is
 * deflate-raw compressed JSON in base64url. Preset codes never start with
 * `0` (their first character is the preset version, from 1), and preset
 * names never start with a digit. The JSON's own format is `DESIGN_FORMAT`.
 */
const DESIGN_VERSION = "0";

/**
 * The newest format of the design JSON, in its `version` key (ADR 0042).
 * A code carries the lowest format that reads it, and none for format 0,
 * so a design without format 1 keys still opens in an older release.
 * Format 1 adds column `format`, `options`, `min`, `max`, `comment` and
 * `identity`, and table `id`, `unique`, `indexes` and `comment`. Format 2
 * adds table `subject` (ADR 0043). Format 3 adds table `rollups` and
 * `lookups` (ADR 0044). Format 4 adds table `events` (ADR 0048) and
 * subject `versions`. Format 5 adds column `access` (ADR 0051).
 */
export const DESIGN_FORMAT = 5;

const FORMAT_1_TABLE_KEYS = ["id", "unique", "indexes", "comment"] as const;

const FORMAT_1_COLUMN_KEYS = [
  "format",
  "options",
  "min",
  "max",
  "comment",
  "identity",
] as const;

/** The lowest design format that reads `design`. */
export function designFormat(design: CreateDesign): number {
  const tables = Object.values(design.appTables ?? {});

  if (
    tables.some((table) =>
      Object.values(table.columns ?? {}).some(
        (column) => column.access !== undefined,
      ),
    )
  ) {
    return 5;
  }

  if (
    tables.some(
      (table) =>
        table.events !== undefined || table.subject?.versions !== undefined,
    )
  ) {
    return 4;
  }

  if (
    tables.some(
      (table) => table.rollups !== undefined || table.lookups !== undefined,
    )
  ) {
    return 3;
  }

  if (tables.some((table) => table.subject !== undefined)) {
    return 2;
  }

  return tables.some(
    (table) =>
      FORMAT_1_TABLE_KEYS.some((key) => table[key] !== undefined) ||
      Object.values(table.columns ?? {}).some((column) =>
        FORMAT_1_COLUMN_KEYS.some((key) => column[key] !== undefined),
      ),
  )
    ? 1
    : 0;
}

/** The longest design code, so a `/create` URL stays under common limits. */
export const MAX_DESIGN_CODE_LENGTH = 6000;

/** The name Create gives the design file it downloads. */
export const DESIGN_FILE = "better-supabase.design.json";

/**
 * Why a design, a design code or a design file was rejected. The codes are
 * stable; the messages may change.
 */
export type DesignErrorCode =
  /** A value has the wrong type, such as a design that isn't an object. */
  | "invalid_design"
  /** A key a design or design file doesn't have. */
  | "unknown_key"
  /** `version` is newer than this release reads (`DESIGN_FORMAT`). */
  | "unsupported_format"
  /** More tables, extra columns or positions than a design may hold. */
  | "too_large"
  /** `extraColumns` names a block that doesn't exist. */
  | "unknown_block"
  /** `extraColumns` names a block that takes no extra columns. */
  | "no_extra_columns"
  /** `extraColumns` names a block the preset doesn't install. */
  | "block_not_installed"
  /** A column or table name that isn't a lower snake identifier. */
  | "invalid_name"
  /** An extra column whose type isn't a SQL type. */
  | "invalid_type"
  /** A canvas position that isn't two finite numbers. */
  | "invalid_position"
  /** An app table that `appTablesOf` rejects. */
  | "invalid_app_table"
  /** A design code that is malformed, damaged or too long to read. */
  | "invalid_code"
  /** A valid design whose code is too long for a URL (`DesignTooLongError`). */
  | "too_long"
  /** A design file that isn't JSON or lacks its keys. */
  | "invalid_file"
  /** A design file's preset that isn't a preset name or code. */
  | "invalid_preset";

/** One problem with a design, as `safeParseDesign` reports it. */
export interface DesignParseIssue {
  readonly code: DesignErrorCode;
  /**
   * A JSON Pointer (RFC 6901) to the key at fault in the value that was
   * read, such as `/appTables/tasks/columns/title`. `""` is the value
   * itself. When the key is missing, it points to the nearest parent.
   */
  readonly path: string;
  readonly message: string;
}

/** What `parseDesign`, `decodeDesign`, `designFileSource` and `readDesignFile` throw. */
export class DesignParseError extends TypeError implements DesignParseIssue {
  readonly code: DesignErrorCode;
  readonly path: string;

  constructor(
    code: DesignErrorCode,
    path: string,
    message: string,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = "DesignParseError";
    this.code = code;
    this.path = path;
  }

  /** The issue as a plain, serializable object. */
  toJSON(): DesignParseIssue {
    return { code: this.code, path: this.path, message: this.message };
  }
}

/** The JSON Pointer to `segments`, escaping `~` and `/`. */
export const jsonPointer = (
  ...segments: readonly (string | number)[]
): string =>
  segments
    .map(
      (segment) =>
        `/${String(segment).replaceAll("~", "~0").replaceAll("/", "~1")}`,
    )
    .join("");

/**
 * What `encodeDesign` throws when a valid design is too long for a URL, so
 * a caller can offer the config download instead of a fix.
 */
export class DesignTooLongError extends DesignParseError {
  /** The length the code would have. */
  readonly length: number;

  constructor(length: number) {
    super(
      "too_long",
      "",
      `design: the code is ${String(length)} characters; the most a URL carries is ${String(MAX_DESIGN_CODE_LENGTH)}. Download the design file instead, then run \`better-supabase init --preset ./${DESIGN_FILE}\`.`,
    );
    this.name = "DesignTooLongError";
    this.length = length;
  }
}

/** The most bytes a design code inflates to; a longer one is rejected. */
const MAX_DESIGN_BYTES = 256 * 1024;

const MAX_TABLES = 100;
const MAX_EXTRA_COLUMNS = 64;
const MAX_POSITIONS = 1000;
const MAX_COORDINATE = 1_000_000;

const DESIGN_CODE = /^0[A-Za-z0-9_-]+$/;
const COLUMN = /^[a-z_][a-z0-9_]{0,62}$/;
const SQL_TYPE = /^[a-z][a-z0-9_ (),.'[\]-]*$/i;
const QUALIFIED = /^[a-z_][a-z0-9_]{0,62}\.[a-z_][a-z0-9_]{0,62}$/;

const isRecord = (value: unknown): value is Readonly<Record<string, unknown>> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** Whether `value` has the shape of a design code. It may still fail to decode. */
export function isDesignCode(value: string): boolean {
  return value.length <= MAX_DESIGN_CODE_LENGTH && DESIGN_CODE.test(value);
}

function extraColumnsOf(
  value: unknown,
  catalog: PresetCatalog,
): CreateDesign["extraColumns"] {
  if (!isRecord(value)) {
    throw new DesignParseError(
      "invalid_design",
      "/extraColumns",
      "design.extraColumns must be an object",
    );
  }

  return Object.fromEntries(
    Object.entries(value).map(([module, columns]) => {
      const at = `design.extraColumns.${module}`;
      const path = jsonPointer("extraColumns", module);
      const block = catalog.blocks.find((each) => each.name === module);

      if (block === undefined) {
        throw new DesignParseError(
          "unknown_block",
          path,
          `${at}: "${module}" is not a block`,
        );
      }

      if (block.extraColumns === undefined) {
        throw new DesignParseError(
          "no_extra_columns",
          path,
          `${at}: the ${module} block takes no extra columns`,
        );
      }

      if (!isRecord(columns)) {
        throw new DesignParseError(
          "invalid_design",
          path,
          `${at} must be an object of column name to SQL type`,
        );
      }

      const entries = Object.entries(columns);

      if (entries.length > MAX_EXTRA_COLUMNS) {
        throw new DesignParseError(
          "too_large",
          path,
          `${at} has ${String(entries.length)} columns; the most is ${String(MAX_EXTRA_COLUMNS)}`,
        );
      }

      const checked: Record<string, string> = {};

      for (const [name, type] of entries) {
        if (!COLUMN.test(name)) {
          throw new DesignParseError(
            "invalid_name",
            jsonPointer("extraColumns", module, name),
            `${at}: "${name}" is not a valid column name`,
          );
        }

        if (
          typeof type !== "string" ||
          !SQL_TYPE.test(type) ||
          type.includes("--")
        ) {
          throw new DesignParseError(
            "invalid_type",
            jsonPointer("extraColumns", module, name),
            `${at}.${name} must be a SQL type such as "text not null default ''"`,
          );
        }

        checked[name] = type;
      }

      return [module, checked];
    }),
  );
}

function coordinate(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    Math.abs(value) <= MAX_COORDINATE
  );
}

function pairOf(value: unknown): readonly [number, number] | undefined {
  if (!Array.isArray(value) || value.length !== 2) {
    return undefined;
  }

  const x: unknown = value[0];
  const y: unknown = value[1];

  return coordinate(x) && coordinate(y) ? [x, y] : undefined;
}

function positionsOf(value: unknown): CreateDesign["positions"] {
  if (!isRecord(value)) {
    throw new DesignParseError(
      "invalid_design",
      "/positions",
      "design.positions must be an object",
    );
  }

  const entries = Object.entries(value);

  if (entries.length > MAX_POSITIONS) {
    throw new DesignParseError(
      "too_large",
      "/positions",
      `design.positions has ${String(entries.length)} entries; the most is ${String(MAX_POSITIONS)}`,
    );
  }

  return Object.fromEntries(
    entries.map(([table, position]) => {
      if (!QUALIFIED.test(table)) {
        throw new DesignParseError(
          "invalid_name",
          jsonPointer("positions", table),
          `design.positions: "${table}" is not a schema.table name`,
        );
      }

      const pair = pairOf(position);

      if (pair === undefined) {
        throw new DesignParseError(
          "invalid_position",
          jsonPointer("positions", table),
          `design.positions.${table} must be [x, y], two finite numbers`,
        );
      }

      return [table, pair];
    }),
  );
}

/**
 * Checks a design object, such as one from storage or a request body, and
 * drops its empty parts. It runs the same checks as `decodeDesign`, without
 * the code. Throws a `DesignParseError` naming the first problem;
 * `safeParseDesign` returns it instead.
 */
export function parseDesign(value: unknown): CreateDesign {
  return designOfValue(value);
}

/** What `safeParseDesign` and `safeDesignFileSource` return. */
export type DesignParseResult<T> =
  | ({ readonly ok: true } & T)
  | { readonly ok: false; readonly issues: readonly DesignParseIssue[] };

const messageOf = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

function issuesOf(error: unknown): readonly DesignParseIssue[] {
  return [
    error instanceof DesignParseError
      ? error.toJSON()
      : { code: "invalid_design", path: "", message: messageOf(error) },
  ];
}

/**
 * `parseDesign` without the throw: the design, or the issue that stopped
 * it, with a stable `code` and a JSON Pointer `path`.
 */
export function safeParseDesign(
  value: unknown,
): DesignParseResult<{ readonly design: CreateDesign }> {
  try {
    return { ok: true, design: designOfValue(value) };
  } catch (error) {
    return { ok: false, issues: issuesOf(error) };
  }
}

/** The keys of a JSON Pointer, unescaped. */
const pointerKeys = (path: string): readonly string[] =>
  path === ""
    ? []
    : path
        .slice(1)
        .split("/")
        .map((key) => key.replaceAll("~1", "/").replaceAll("~0", "~"));

/**
 * A Standard Schema (v1) for a design, so a form library, a router or an
 * AI SDK tool can validate one with the same rules as `parseDesign`. The
 * output drops the empty parts; each issue's `path` lists the keys of its
 * JSON Pointer. `schemas/design-v1.json` is the JSON Schema of its shape.
 */
export const designSchema: StandardSchemaV1<unknown, CreateDesign> = {
  "~standard": {
    version: 1,
    vendor: "better-supabase",
    validate(value) {
      const result = safeParseDesign(value);

      return result.ok
        ? { value: result.design }
        : {
            issues: result.issues.map((issue) => ({
              message: issue.message,
              path: pointerKeys(issue.path),
            })),
          };
    },
  },
};

const SEGMENT_CHAR = /[A-Za-z0-9_]/;
const INDEX_SEGMENT = /^\[(\d+)\]/;
const TRAILING_KEY = /^\.([A-Za-z0-9_]+)(?=[\s:]|$)/;

/** The longest key of `node` that `rest` starts with, after a dot. */
function keyAt(
  node: Readonly<Record<string, unknown>>,
  rest: string,
): string | undefined {
  return Object.keys(node)
    .filter(
      (each) =>
        rest.startsWith(`.${each}`) &&
        !SEGMENT_CHAR.test(rest.charAt(each.length + 1)),
    )
    .toSorted((a, b) => b.length - a.length)[0];
}

/**
 * The JSON Pointer for an `appTablesOf` message, which starts with the
 * dotted path it rejects (`appTables.tasks.columns.title must be...`). It
 * walks `value` so a key with a dot or a space still resolves.
 */
function appTablesPointer(message: string, value: unknown): string {
  const segments: (string | number)[] = ["appTables"];
  let rest = message.startsWith("appTables") ? message.slice(9) : "";
  let current = value;

  for (;;) {
    const index = INDEX_SEGMENT.exec(rest);

    if (index !== null && Array.isArray(current)) {
      const at = Number(index[1]);
      segments.push(at);
      current = current[at];
      rest = rest.slice(index[0].length);
      continue;
    }

    const node = current;
    const key = isRecord(node) ? keyAt(node, rest) : undefined;

    if (key === undefined || !isRecord(node)) {
      break;
    }

    segments.push(key);
    current = node[key];
    rest = rest.slice(key.length + 1);
  }

  const trailing = TRAILING_KEY.exec(rest);

  if (trailing?.[1] !== undefined) {
    segments.push(trailing[1]);
  }

  return jsonPointer(...segments);
}

function checkedAppTables(
  value: unknown,
  tenantName?: string,
): AppTablesConfig {
  try {
    return appTablesOf(value, tenantName);
  } catch (error) {
    if (!(error instanceof TypeError) || error instanceof DesignParseError) {
      throw error;
    }

    throw new DesignParseError(
      "invalid_app_table",
      appTablesPointer(error.message, value),
      error.message,
      { cause: error },
    );
  }
}

function designOfValue(
  value: unknown,
  catalog: PresetCatalog = PRESET_CATALOG,
): CreateDesign {
  if (!isRecord(value)) {
    throw new DesignParseError(
      "invalid_design",
      "",
      "design must be an object",
    );
  }

  const unknownKey = Object.keys(value).find(
    (name) =>
      name !== "appTables" &&
      name !== "extraColumns" &&
      name !== "positions" &&
      name !== "version",
  );

  if (unknownKey !== undefined) {
    throw new DesignParseError(
      "unknown_key",
      jsonPointer(unknownKey),
      `design: unknown key "${unknownKey}"; a design has appTables, extraColumns and positions`,
    );
  }

  const version = value["version"] ?? 0;

  if (
    typeof version !== "number" ||
    !Number.isSafeInteger(version) ||
    version < 0
  ) {
    throw new DesignParseError(
      "invalid_design",
      "/version",
      "design.version must be a whole number",
    );
  }

  if (version > DESIGN_FORMAT) {
    throw new DesignParseError(
      "unsupported_format",
      "/version",
      `design: the code needs format ${String(version)}, and this better-supabase reads up to ${String(DESIGN_FORMAT)}; update better-supabase`,
    );
  }

  const appTables =
    value["appTables"] === undefined
      ? {}
      : checkedAppTables(value["appTables"]);

  if (Object.keys(appTables).length > MAX_TABLES) {
    throw new DesignParseError(
      "too_large",
      "/appTables",
      `design.appTables has ${String(Object.keys(appTables).length)} tables; the most is ${String(MAX_TABLES)}`,
    );
  }

  const extraColumns =
    value["extraColumns"] === undefined
      ? {}
      : (extraColumnsOf(value["extraColumns"], catalog) ?? {});

  const positions =
    value["positions"] === undefined
      ? {}
      : (positionsOf(value["positions"]) ?? {});

  const filled = Object.fromEntries(
    Object.entries(extraColumns).filter(
      ([, columns]) => Object.keys(columns).length > 0,
    ),
  );

  return {
    ...(Object.keys(appTables).length === 0 ? {} : { appTables }),
    ...(Object.keys(filled).length === 0 ? {} : { extraColumns: filled }),
    ...(Object.keys(positions).length === 0 ? {} : { positions }),
  };
}

async function pipe(
  bytes: Uint8Array<ArrayBuffer>,
  transform: CompressionStream | DecompressionStream,
  limit: number,
): Promise<Uint8Array> {
  const reader = new Blob([bytes]).stream().pipeThrough(transform).getReader();

  const chunks: Uint8Array[] = [];
  let length = 0;

  for (;;) {
    const { done, value } = await reader.read();

    if (done) {
      break;
    }

    length += value.byteLength;

    if (length > limit) {
      await reader.cancel();

      throw new DesignParseError(
        "invalid_code",
        "",
        `design: the code inflates past ${String(limit)} bytes`,
      );
    }

    chunks.push(value);
  }

  const out = new Uint8Array(length);
  let offset = 0;

  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }

  return out;
}

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCodePoint(byte);
  }

  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

function fromBase64Url(text: string): Uint8Array<ArrayBuffer> {
  const binary = atob(text.replaceAll("-", "+").replaceAll("_", "/"));

  return Uint8Array.from(binary, (char) => char.codePointAt(0) ?? 0);
}

/**
 * The design as a code for the `&design=` parameter: `0`, then its JSON
 * (with `version` set to `designFormat` when it is above 0) compressed with
 * deflate-raw, in base64url. An empty design is `""`.
 * Throws a `DesignParseError` when the design is invalid, and a `DesignTooLongError`
 * when the code would be longer than `MAX_DESIGN_CODE_LENGTH`.
 */
export async function encodeDesign(design: CreateDesign): Promise<string> {
  const checked = designOfValue(design);

  if (Object.keys(checked).length === 0) {
    return "";
  }

  const format = designFormat(checked);

  const json = new TextEncoder().encode(
    JSON.stringify(format === 0 ? checked : { version: format, ...checked }),
  );

  const code = `${DESIGN_VERSION}${toBase64Url(
    await pipe(json, new CompressionStream("deflate-raw"), MAX_DESIGN_BYTES),
  )}`;

  if (code.length > MAX_DESIGN_CODE_LENGTH) {
    throw new DesignTooLongError(code.length);
  }

  return code;
}

/** Reads a design code. Throws a `DesignParseError` when it isn't a valid one. */
export async function decodeDesign(code: string): Promise<CreateDesign> {
  if (code === "") {
    return {};
  }

  if (!isDesignCode(code)) {
    throw new DesignParseError(
      "invalid_code",
      "",
      code.length > MAX_DESIGN_CODE_LENGTH
        ? `design: the code is longer than ${String(MAX_DESIGN_CODE_LENGTH)} characters`
        : `design: "${code.slice(0, 40)}" is not a design code`,
    );
  }

  let json: unknown;

  try {
    const bytes = await pipe(
      fromBase64Url(code.slice(DESIGN_VERSION.length)),
      new DecompressionStream("deflate-raw"),
      MAX_DESIGN_BYTES,
    );

    json = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch (error) {
    if (error instanceof DesignParseError) {
      throw error;
    }

    throw new DesignParseError(
      "invalid_code",
      "",
      "design: the code is damaged; copy it again from /create",
      { cause: error },
    );
  }

  return designOfValue(json);
}

/**
 * The design in a `/create` URL's `&design=` parameter, or in a bare design
 * code; `undefined` when `input` has neither.
 */
export async function designOf(
  input: string,
): Promise<CreateDesign | undefined> {
  const parameter = /[?&]design=([^&#]*)/.exec(input)?.[1];

  if (parameter !== undefined) {
    return decodeDesign(decodeURIComponent(parameter));
  }

  return isDesignCode(input) ? decodeDesign(input) : undefined;
}

/**
 * The config keys a preset with a design sets: `presetConfig`, with each
 * block's `options.extraColumns` and `appTables`. Throws a `DesignParseError` when the
 * design adds columns to a block the preset doesn't install.
 */
export function designConfig(
  resolved: ResolvedPreset,
  design: CreateDesign,
): ReturnType<typeof presetConfig> & { readonly appTables?: AppTablesConfig } {
  const base = presetConfig(resolved);

  const blocks: Record<string, BlockConfig | AccessBlockConfig | undefined> = {
    ...base.blocks,
  };

  for (const [module, columns] of Object.entries(design.extraColumns ?? {})) {
    const entry = blocks[module];

    if (entry === undefined) {
      throw new DesignParseError(
        "block_not_installed",
        jsonPointer("extraColumns", module),
        `design.extraColumns.${module}: the preset doesn't install the ${module} block`,
      );
    }

    blocks[module] = {
      ...entry,
      options: { ...entry.options, extraColumns: columns },
    };
  }

  const appTables =
    design.appTables === undefined
      ? {}
      : checkedAppTables(design.appTables, resolved.preset.tenantName);

  return {
    ...base,
    blocks,
    ...(Object.keys(appTables).length === 0 ? {} : { appTables }),
  };
}

/**
 * `better-supabase.config.ts` for a preset with a design. `designCode`, the
 * design's `encodeDesign`, goes into the `/create` URL in the comment, so the
 * canvas reopens with its positions.
 */
export function designConfigSource(
  resolved: ResolvedPreset,
  design: CreateDesign,
  designCode = "",
): string {
  const config: ConfigSourceKeys = designConfig(resolved, design);

  return configSource(resolved, config, createUrl(resolved, designCode));
}

/**
 * The command that starts a project from the preset and design: `init` with
 * the quoted `/create` URL, or `presetInstallCommand` when `designCode` is
 * empty.
 */
export function designInstallCommand(
  resolved: ResolvedPreset,
  designCode: string,
): string {
  return designCode === ""
    ? presetInstallCommand(resolved)
    : `npx better-supabase init --preset "${createUrl(resolved, designCode)}"`;
}

/**
 * A preset and its design as one JSON file, for a design too long for a URL
 * (ADR 0058). `init --preset` and `apply --preset` read it from a path.
 */
export interface DesignFile {
  /** The preset code. */
  readonly preset: string;
  /** The design, with `version` set to `designFormat` when it is above 0. */
  readonly design: CreateDesign & { readonly version?: number };
}

/**
 * The design file for a preset and design, as JSON text. Throws a
 * `DesignParseError` when the design is invalid; `safeDesignFileSource`
 * returns it instead. It has no length limit.
 */
export function designFileSource(
  resolved: ResolvedPreset,
  design: CreateDesign,
): string {
  const checked = designOfValue(design);
  const format = designFormat(checked);

  const file: DesignFile = {
    preset: encodePreset(resolved.preset),
    design: format === 0 ? checked : { version: format, ...checked },
  };

  return `${JSON.stringify(file, null, 2)}\n`;
}

/**
 * `designFileSource` without the throw: the file text, or the issue that
 * stopped it. Each `path` points into the design.
 */
export function safeDesignFileSource(
  resolved: ResolvedPreset,
  design: CreateDesign,
): DesignParseResult<{ readonly source: string }> {
  try {
    return { ok: true, source: designFileSource(resolved, design) };
  } catch (error) {
    return { ok: false, issues: issuesOf(error) };
  }
}

/**
 * Reads a design file's text. Each `DesignParseError` path points into the
 * file, so a design problem starts with `/design`. Throws one naming the
 * first problem:
 * text that isn't JSON, a missing or invalid preset, or an invalid design.
 */
export function readDesignFile(text: string): {
  readonly preset: Preset;
  readonly design: CreateDesign;
} {
  let value: unknown;

  try {
    value = JSON.parse(text);
  } catch (error) {
    throw new DesignParseError(
      "invalid_file",
      "",
      "design file: the text is not JSON",
      { cause: error },
    );
  }

  if (!isRecord(value)) {
    throw new DesignParseError(
      "invalid_file",
      "",
      "design file: expected an object with preset and design",
    );
  }

  const unknownKey = Object.keys(value).find(
    (name) => name !== "preset" && name !== "design",
  );

  if (unknownKey !== undefined) {
    throw new DesignParseError(
      "unknown_key",
      jsonPointer(unknownKey),
      `design file: unknown key "${unknownKey}"; a design file has preset and design`,
    );
  }

  const preset = value["preset"];

  if (typeof preset !== "string" || preset === "") {
    throw new DesignParseError(
      "invalid_preset",
      "/preset",
      "design file: preset must be a preset name or code from /create",
    );
  }

  let parsed: Preset;

  try {
    parsed = presetOf(preset);
  } catch (error) {
    throw new DesignParseError("invalid_preset", "/preset", messageOf(error), {
      cause: error,
    });
  }

  try {
    return { preset: parsed, design: designOfValue(value["design"] ?? {}) };
  } catch (error) {
    if (error instanceof DesignParseError) {
      throw new DesignParseError(
        error.code,
        `/design${error.path}`,
        error.message,
        { cause: error },
      );
    }

    throw error;
  }
}

/** The command that applies the preset and design to an existing project. */
export function designApplyCommand(
  resolved: ResolvedPreset,
  designCode: string,
): string {
  return designCode === ""
    ? presetApplyCommand(resolved)
    : `npx better-supabase apply --preset "${createUrl(resolved, designCode)}"`;
}
