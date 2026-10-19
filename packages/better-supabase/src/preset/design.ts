import type { AccessBlockConfig, BlockConfig } from "../config/blocks.ts";
import type {
  AppTableConfig,
  AppTablesConfig,
} from "../config/types/app-tables.ts";
import type { PresetCatalog } from "./catalog-types.ts";
import type { ResolvedPreset } from "./resolve.ts";

import { appTablesOf } from "../config/app-tables.ts";
import { PRESET_CATALOG } from "./catalog.generated.ts";
import { presetConfig } from "./config.ts";
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
 * `lookups` (ADR 0044). Format 4 adds table `events` (ADR 0048).
 */
export const DESIGN_FORMAT = 4;

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

  if (tables.some((table) => table.events !== undefined)) {
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

/**
 * What `encodeDesign` throws when a valid design is too long for a URL, so
 * a caller can offer the config download instead of a fix.
 */
export class DesignTooLongError extends TypeError {
  /** The length the code would have. */
  readonly length: number;

  constructor(length: number) {
    super(
      `design: the code is ${String(length)} characters; the most a URL carries is ${String(MAX_DESIGN_CODE_LENGTH)}. Download the config instead, save it as better-supabase.config.ts, then run \`better-supabase init\` and \`better-supabase sql sync\`.`,
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
    throw new TypeError("design.extraColumns must be an object");
  }

  return Object.fromEntries(
    Object.entries(value).map(([module, columns]) => {
      const at = `design.extraColumns.${module}`;
      const block = catalog.blocks.find((each) => each.name === module);

      if (block === undefined) {
        throw new TypeError(`${at}: "${module}" is not a block`);
      }

      if (block.extraColumns === undefined) {
        throw new TypeError(
          `${at}: the ${module} block takes no extra columns`,
        );
      }

      if (!isRecord(columns)) {
        throw new TypeError(
          `${at} must be an object of column name to SQL type`,
        );
      }

      const entries = Object.entries(columns);

      if (entries.length > MAX_EXTRA_COLUMNS) {
        throw new TypeError(
          `${at} has ${String(entries.length)} columns; the most is ${String(MAX_EXTRA_COLUMNS)}`,
        );
      }

      const checked: Record<string, string> = {};

      for (const [name, type] of entries) {
        if (!COLUMN.test(name)) {
          throw new TypeError(`${at}: "${name}" is not a valid column name`);
        }

        if (
          typeof type !== "string" ||
          !SQL_TYPE.test(type) ||
          type.includes("--")
        ) {
          throw new TypeError(
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
    throw new TypeError("design.positions must be an object");
  }

  const entries = Object.entries(value);

  if (entries.length > MAX_POSITIONS) {
    throw new TypeError(
      `design.positions has ${String(entries.length)} entries; the most is ${String(MAX_POSITIONS)}`,
    );
  }

  return Object.fromEntries(
    entries.map(([table, position]) => {
      if (!QUALIFIED.test(table)) {
        throw new TypeError(
          `design.positions: "${table}" is not a schema.table name`,
        );
      }

      const pair = pairOf(position);

      if (pair === undefined) {
        throw new TypeError(
          `design.positions.${table} must be [x, y], two finite numbers`,
        );
      }

      return [table, pair];
    }),
  );
}

/**
 * Checks a design and drops its empty parts. Throws a TypeError naming the
 * first problem.
 */
function designOfValue(
  value: unknown,
  catalog: PresetCatalog = PRESET_CATALOG,
): CreateDesign {
  if (!isRecord(value)) {
    throw new TypeError("design must be an object");
  }

  const unknownKey = Object.keys(value).find(
    (name) =>
      name !== "appTables" &&
      name !== "extraColumns" &&
      name !== "positions" &&
      name !== "version",
  );

  if (unknownKey !== undefined) {
    throw new TypeError(
      `design: unknown key "${unknownKey}"; a design has appTables, extraColumns and positions`,
    );
  }

  const version = value["version"] ?? 0;

  if (
    typeof version !== "number" ||
    !Number.isSafeInteger(version) ||
    version < 0
  ) {
    throw new TypeError("design.version must be a whole number");
  }

  if (version > DESIGN_FORMAT) {
    throw new TypeError(
      `design: the code needs format ${String(version)}, and this better-supabase reads up to ${String(DESIGN_FORMAT)}; update better-supabase`,
    );
  }

  const appTables =
    value["appTables"] === undefined ? {} : appTablesOf(value["appTables"]);

  if (Object.keys(appTables).length > MAX_TABLES) {
    throw new TypeError(
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

      throw new TypeError(
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
 * Throws a TypeError when the design is invalid, and a `DesignTooLongError`
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

/** Reads a design code. Throws a TypeError when it isn't a valid one. */
export async function decodeDesign(code: string): Promise<CreateDesign> {
  if (code === "") {
    return {};
  }

  if (!isDesignCode(code)) {
    throw new TypeError(
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
    if (error instanceof TypeError && error.message.startsWith("design:")) {
      throw error;
    }

    throw new TypeError(
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
 * block's `options.extraColumns` and `appTables`. Throws a TypeError when the
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
      throw new TypeError(
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
      : appTablesOf(design.appTables, resolved.preset.tenantName);

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

/** The command that applies the preset and design to an existing project. */
export function designApplyCommand(
  resolved: ResolvedPreset,
  designCode: string,
): string {
  return designCode === ""
    ? presetApplyCommand(resolved)
    : `npx better-supabase apply --preset "${createUrl(resolved, designCode)}"`;
}
