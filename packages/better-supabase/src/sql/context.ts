import type { ClaimsMeta } from "../schema/types.ts";

import {
  type KitMode,
  type KitsConfig,
  type ResolvedKitModule,
  resolveKitModule,
} from "../config/kits.ts";
import { DEFAULT_CLAIMS } from "../core/claims.ts";
import { sqlIdent, sqlString } from "../core/template.ts";

/** The scope id types kit modules render. */
export const KIT_ID_TYPES = ["uuid", "text", "bigint", "integer"] as const;
export type KitIdType = (typeof KIT_ID_TYPES)[number];

export const isKitIdType = (value: string): value is KitIdType =>
  KIT_ID_TYPES.some((type) => type === value);

const ID_TYPE_ALIASES: Readonly<Record<string, KitIdType>> = {
  int8: "bigint",
  int4: "integer",
  int: "integer",
  varchar: "text",
  "character varying": "text",
};

/**
 * A Postgres type name as one of `KIT_ID_TYPES`: case and spacing are
 * normalised and aliases such as `int8` resolved. `undefined` for any other
 * type, so callers refuse it instead of guessing.
 */
export function kitIdType(value: string): KitIdType | undefined {
  const name = value.trim().toLowerCase().replaceAll(/\s+/g, " ");
  return isKitIdType(name) ? name : ID_TYPE_ALIASES[name];
}

/** One logical table of a module: its default name and logical columns. */
export interface KitTableSpec {
  /** Default name, in the module's schema. */
  readonly name: string;
  /** Logical column to default column name. */
  readonly columns: Readonly<Record<string, string>>;
  /**
   * Logical columns an adopted table may lack (mapped to `null`): the module
   * leaves out the feature that needs them.
   */
  readonly optional?: readonly string[];
  /** The app may lack the whole table (`kits.<name>.tables.<table>: null`). */
  readonly optionalTable?: boolean;
}

export interface KitNames {
  readonly tables: Readonly<Record<string, KitTableSpec>>;
  /** The `before_*` and `after_*` hooks the module calls, so `kits.<name>.hooks.functions` is checked. */
  readonly hooks?: readonly string[];
}

/** An event a module writes to the outbox, as SQL expressions. */
export interface KitEmit {
  /** The event type, e.g. `org.created`. */
  readonly type: string;
  /** A `jsonb` expression. */
  readonly payload: string;
  /** A `text` expression, e.g. `'organizations/' || new_org`. */
  readonly subject?: string;
  /** The tenant id expression; it is cast to text. */
  readonly tenant?: string;
  /** A `text` idempotency key expression. */
  readonly key?: string;
}

/** A function of a module's contract: what other modules and the TypeScript side call. */
export interface KitContractFunction {
  readonly name: string;
  /** Argument types; `{id}` stands for the module's id type. */
  readonly args: readonly string[];
  readonly returns: string;
}

/** What a module's `build` reads: resolved names for one layout. */
export interface KitContext {
  readonly module: string;
  readonly mode: KitMode;
  readonly config: ResolvedKitModule;
  /** The quoted schema of the module's functions and managed tables. */
  readonly schema: string;
  readonly schemaName: string;
  readonly idType: KitIdType;
  readonly claims: ClaimsMeta;
  readonly kits: KitsConfig;
  /** `schema.name` of a module function, quoted. */
  fn(name: string): string;
  /** `schema.table` of a logical table, quoted. */
  table(logical: string): string;
  /** The unquoted schema and name of a logical table. */
  tableName(logical: string): {
    readonly schema: string;
    readonly name: string;
  };
  /** A logical column, quoted. Throws when an adopted table lacks it. */
  col(table: string, column: string): string;
  /** Whether a logical column exists (adopted tables can map it to `null`). */
  has(table: string, column: string): boolean;
  /** Whether an optional logical table exists (it can be mapped to `null`). */
  hasTable(table: string): boolean;
  /** Whether the module owns `table` (managed mode). */
  readonly manages: boolean;
  /** The permission key for a kit action, as a SQL literal. */
  permission(action: string, fallback: string): string;
  /** The permission key for a kit action. */
  permissionKey(action: string, fallback: string): string;
  /** A trigger name with the module's prefix, quoted. */
  trigger(name: string): string;
  /** Whether `module` is installed alongside this one. */
  installed(module: string): boolean;
  /** The context of another module in the same layout. */
  of(module: string): KitContext;
  /** A string module option (`kits.<name>.options`). */
  text(name: string, fallback: string): string;
  number(name: string, fallback: number): number;
  flag(name: string, fallback: boolean): boolean;
  /** A module option that is a list of strings. */
  list(name: string, fallback: readonly string[]): readonly string[];
  /**
   * PL/pgSQL that calls the app's hook function when it exists, with
   * `[type, expression]` arguments: `if to_regprocedure(...) is not null
   * then perform ...; end if;`.
   */
  hook(name: string, args: readonly (readonly [string, string])[]): string;
  /** The app function a hook calls, quoted, for hooks that return a value. */
  hookTarget(name: string): string;
  /**
   * PL/pgSQL that writes the event to the outbox (`emit_event`) when the
   * `outbox` module is installed and `kits.<name>.events` isn't false;
   * otherwise an empty string.
   */
  emit(event: KitEmit): string;
}

export interface KitContextSource {
  readonly kits?: KitsConfig;
  readonly claims?: ClaimsMeta;
  /** The modules being installed together. */
  readonly installed?: readonly string[];
  /** The id type from PermDock's manifest, when the layout has one. */
  readonly permdockIdType?: KitIdType;
}

const IDENT = /^[A-Za-z_][A-Za-z0-9_$]*$/;

function splitTable(
  value: string,
  schema: string,
): { readonly schema: string; readonly name: string } {
  const dot = value.indexOf(".");
  return dot === -1
    ? { schema, name: value }
    : { schema: value.slice(0, dot), name: value.slice(dot + 1) };
}

function checkIdent(where: string, value: string): string {
  if (!IDENT.test(value) || value.length > 63) {
    throw new TypeError(`${where}: "${value}" is not a valid identifier`);
  }
  return value;
}

/**
 * Builds the context for `module`. `namesOf` looks up a module's names, so a
 * module can name another module's tables through `of()`.
 */
export function createKitContext(
  module: string,
  namesOf: (name: string) => KitNames | undefined,
  source: KitContextSource = {},
): KitContext {
  const kits = source.kits ?? {};
  const config = resolveKitModule(kits[module]);
  const where = `kits.${module}`;
  const names = namesOf(module) ?? { tables: {} };
  checkIdent(`${where}.schema`, config.schema);

  for (const [table, name] of Object.entries(config.tables)) {
    const known = names.tables[table];
    if (!known) {
      throw new TypeError(
        `${where}.tables: unknown table "${table}". Tables: ${Object.keys(names.tables).join(", ") || "none"}`,
      );
    }
    if (name === null && !known.optionalTable) {
      throw new TypeError(
        `${where}.tables.${table} is required and can't be null`,
      );
    }
  }
  for (const [table, columns] of Object.entries(config.columns)) {
    const known = names.tables[table];
    if (!known) {
      throw new TypeError(
        `${where}.columns: unknown table "${table}". Tables: ${Object.keys(names.tables).join(", ") || "none"}`,
      );
    }
    for (const [column, name] of Object.entries(columns)) {
      if (!(column in known.columns)) {
        throw new TypeError(
          `${where}.columns.${table}: unknown column "${column}". Columns: ${Object.keys(known.columns).join(", ")}`,
        );
      }
      if (name === null) {
        if (!known.optional?.includes(column)) {
          throw new TypeError(
            `${where}.columns.${table}.${column} is required and can't be null`,
          );
        }
      } else checkIdent(`${where}.columns.${table}.${column}`, name);
    }
  }

  checkIdent(`${where}.hooks.schema`, config.hooks.schema);
  for (const [hook, target] of Object.entries(config.hooks.functions)) {
    if (!names.hooks?.includes(hook)) {
      throw new TypeError(
        `${where}.hooks.functions: unknown hook "${hook}". Hooks: ${names.hooks?.length ? names.hooks.join(", ") : "none"}`,
      );
    }
    const parts = splitTable(target, config.hooks.schema);
    checkIdent(`${where}.hooks.functions.${hook}`, parts.schema);
    checkIdent(`${where}.hooks.functions.${hook}`, parts.name);
  }

  const rawId =
    config.idType ?? kits.access?.idType ?? source.permdockIdType ?? "uuid";
  const idType = kitIdType(rawId);
  if (!idType) {
    throw new TypeError(
      `${where}.idType: "${rawId}" is not one of ${KIT_ID_TYPES.join(", ")}`,
    );
  }

  const tableName = (logical: string) => {
    const table = names.tables[logical];
    if (!table) {
      throw new TypeError(`Module "${module}" has no table "${logical}"`);
    }
    const mapped = config.tables[logical];
    if (mapped === null) {
      throw new TypeError(
        `Module "${module}" needs table "${logical}", which kits.${module}.tables maps to null`,
      );
    }
    const parts = splitTable(mapped ?? table.name, config.schema);
    checkIdent(`${where}.tables.${logical}`, parts.schema);
    checkIdent(`${where}.tables.${logical}`, parts.name);
    return parts;
  };
  const column = (table: string, logical: string): string | null => {
    const known = names.tables[table];
    if (!known || !(logical in known.columns)) {
      throw new TypeError(
        `Module "${module}" has no column "${table}.${logical}"`,
      );
    }
    const mapped = config.columns[table]?.[logical];
    return mapped === undefined ? known.columns[logical]! : mapped;
  };
  function optionOf(name: string, type: "string", fallback: string): string;
  function optionOf(name: string, type: "number", fallback: number): number;
  function optionOf(name: string, type: "boolean", fallback: boolean): boolean;
  function optionOf(
    name: string,
    type: "string" | "number" | "boolean",
    fallback: string | number | boolean,
  ): string | number | boolean {
    const value = config.options[name];
    if (value === undefined) return fallback;
    if (
      typeof value !== "string" &&
      typeof value !== "number" &&
      typeof value !== "boolean"
    ) {
      throw new TypeError(`${where}.options.${name} must be a ${type}`);
    }
    if (typeof value !== type) {
      throw new TypeError(`${where}.options.${name} must be a ${type}`);
    }
    return value;
  }
  const schema = sqlIdent(config.schema);
  const hookTarget = (name: string): string => {
    if (!names.hooks?.includes(name)) {
      throw new TypeError(`Module "${module}" declares no hook "${name}"`);
    }
    const parts = splitTable(
      config.hooks.functions[name] ?? name,
      config.hooks.schema,
    );
    return `${sqlIdent(parts.schema)}.${sqlIdent(parts.name)}`;
  };
  const installed = new Set(source.installed ?? [module]);

  return {
    module,
    mode: config.mode,
    config,
    schema,
    schemaName: config.schema,
    idType,
    claims: source.claims ?? DEFAULT_CLAIMS,
    kits,
    manages: config.mode === "managed",
    fn: (name) => `${schema}.${sqlIdent(name)}`,
    tableName,
    table(logical) {
      const parts = tableName(logical);
      return `${sqlIdent(parts.schema)}.${sqlIdent(parts.name)}`;
    },
    col(table, logical) {
      const name = column(table, logical);
      if (name === null) {
        throw new TypeError(
          `Module "${module}" needs ${table}.${logical}, which kits.${module}.columns maps to null`,
        );
      }
      return sqlIdent(name);
    },
    has: (table, logical) =>
      config.tables[table] !== null && column(table, logical) !== null,
    hasTable: (table) => {
      if (!names.tables[table]) {
        throw new TypeError(`Module "${module}" has no table "${table}"`);
      }
      return config.tables[table] !== null;
    },
    permissionKey: (action, fallback) => config.permissions[action] ?? fallback,
    permission: (action, fallback) =>
      sqlString(config.permissions[action] ?? fallback),
    trigger: (name) => sqlIdent(`${config.triggerPrefix}${name}`),
    installed: (name) => installed.has(name),
    of: (name) => createKitContext(name, namesOf, source),
    text: (name, fallback) => optionOf(name, "string", fallback),
    number: (name, fallback) => optionOf(name, "number", fallback),
    flag: (name, fallback) => optionOf(name, "boolean", fallback),
    list(name, fallback) {
      const value = config.options[name];
      if (value === undefined) return fallback;
      if (
        !Array.isArray(value) ||
        !value.every((item) => typeof item === "string")
      ) {
        throw new TypeError(`${where}.options.${name} must be a string array`);
      }
      return value;
    },
    hook(name, args) {
      const target = hookTarget(name);
      const types = args.map(([type]) => type).join(", ");
      return `if to_regprocedure(${sqlString(`${target}(${types})`)}) is not null then
    perform ${target}(${args.map(([, value]) => value).join(", ")});
  end if;`;
    },
    hookTarget,
    emit(event) {
      if (!config.events || !installed.has("outbox")) return "";
      const outboxConfig = resolveKitModule(kits["outbox"]);
      const outbox = sqlIdent(outboxConfig.schema);
      const template =
        outboxConfig.options["kitSource"] ?? "better-supabase/{module}";
      if (typeof template !== "string") {
        throw new TypeError("kits.outbox.options.kitSource must be a string");
      }
      return `perform ${outbox}.emit_event(${[
        sqlString(event.type),
        event.payload,
        event.subject ?? "null",
        event.tenant === undefined ? "null" : `(${event.tenant})::text`,
        event.key ?? "null",
        sqlString(template.replaceAll("{module}", module)),
      ].join(", ")});`;
    },
  };
}

/** The contract's argument list with `{id}` resolved, as Postgres prints it. */
export function contractSignature(
  fn: KitContractFunction,
  idType: string,
): string {
  return fn.args.map((arg) => arg.replaceAll("{id}", idType)).join(", ");
}
