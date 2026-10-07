import type { ColumnMeta, SchemaMeta, TableMeta } from "../schema/types.ts";

/** What field planning reads: the metadata and the typed-jsonb config. */
export interface SchemaSource {
  readonly meta: SchemaMeta;
  readonly config: { readonly json: Readonly<Record<string, unknown>> };
}

export type Variant = "Row" | "Insert" | "Update";

/** Validator for one scalar, independent of the target library. */
export type ScalarKind =
  | { readonly kind: "uuid" }
  | { readonly kind: "string" }
  | { readonly kind: "integer" }
  | { readonly kind: "number" }
  | { readonly kind: "boolean" }
  | { readonly kind: "datetime" }
  | { readonly kind: "date" }
  | { readonly kind: "instant" }
  | { readonly kind: "plainDateTime" }
  | { readonly kind: "bigint" }
  | { readonly kind: "json" }
  | { readonly kind: "enum"; readonly values: readonly string[] }
  | { readonly kind: "unknown" };

const INTEGER = new Set(["int2", "int4", "int8"]);
const NUMBER = new Set(["float4", "float8", "numeric", "oid", "money"]);
// `timestamp` values have no offset, so they stay plain strings.
const DATETIME = new Set(["timestamptz"]);

function scalarKind(column: ColumnMeta): ScalarKind {
  if (column.enum) return { kind: "enum", values: column.enum };
  if (column.json) return { kind: "json" };
  if (column.codec === "instant") return { kind: "instant" };
  if (column.codec === "plainDateTime") return { kind: "plainDateTime" };
  if (column.codec === "bigint") return { kind: "bigint" };
  if (column.codec === "string") return { kind: "string" };
  if (column.type === "uuid") return { kind: "uuid" };
  if (INTEGER.has(column.type)) return { kind: "integer" };
  if (NUMBER.has(column.type)) return { kind: "number" };
  if (column.type === "bool") return { kind: "boolean" };
  if (DATETIME.has(column.type)) return { kind: "datetime" };
  if (column.type === "date") return { kind: "date" };
  if (column.type === "record" || column.type === "void")
    return { kind: "unknown" };
  return { kind: "string" };
}

export interface FieldPlan {
  readonly name: string;
  readonly column: ColumnMeta;
  readonly scalar: ScalarKind;
  readonly nullable: boolean;
  readonly optional: boolean;
  /** Set when the config gives this jsonb column a custom TypeScript type. */
  readonly customJson: boolean;
  /** Filled by `timestamps()`, `actor()` or `softDelete()`; writes need `{ override: true }`. */
  readonly managed: boolean;
}

/** App names of the columns that plugins fill from the table's flags. */
function managedColumns(table: TableMeta): ReadonlySet<string> {
  const { timestamps, actor, softDelete } = table.flags;
  return new Set(
    [
      timestamps?.createdAt,
      timestamps?.updatedAt,
      actor?.createdBy,
      actor?.updatedBy,
      actor?.impersonatedBy,
      softDelete,
    ].filter((name): name is string => name !== undefined),
  );
}

/**
 * The generated row type of a field (its element type for arrays). Storage
 * path columns validate as strings and are cast to their `StoragePath` brand.
 */
export function rowType(table: string, plan: FieldPlan): string {
  const type = `NonNullable<RowOf<'${table}'>['${plan.name}']>`;
  return plan.column.array ? `${type}[number]` : type;
}

/** The fields a variant accepts; read-only columns are left out of writes. */
export function fieldsFor(
  table: TableMeta,
  variant: Variant,
  input: SchemaSource,
): FieldPlan[] {
  const fields: FieldPlan[] = [];
  const managed = managedColumns(table);
  for (const [name, column] of Object.entries(table.columns)) {
    if (
      variant === "Insert" &&
      (column.generated || column.insertable === false)
    )
      continue;
    if (
      variant === "Update" &&
      (column.generated || column.updatable === false)
    )
      continue;
    fields.push({
      name,
      column,
      scalar: scalarKind(column),
      nullable: column.nullable,
      optional:
        variant === "Update" ||
        (variant === "Insert" && (column.nullable || column.hasDefault)),
      customJson: Boolean(
        column.json &&
        (input.config.json[`${table.schema}.${table.name}.${column.db}`] ??
          input.config.json[`${table.name}.${column.db}`]),
      ),
      managed: managed.has(name),
    });
  }
  return fields;
}

const TEMPORAL_GUARDS: Partial<Record<ScalarKind["kind"], string>> = {
  instant: "isInstant",
  plainDateTime: "isPlainDateTime",
};

/**
 * The `better-supabase` guards the generated validators call. They check
 * `Symbol.toStringTag`, so the module never reads `Temporal` when it loads.
 */
export function temporalGuardImport(input: SchemaSource): string | undefined {
  const names = new Set<string>();
  for (const [, table] of tableEntries(input)) {
    for (const plan of fieldsFor(table, "Row", input)) {
      if (plan.customJson || plan.column.storage !== undefined) continue;
      const guard = TEMPORAL_GUARDS[plan.scalar.kind];
      if (guard) names.add(guard);
    }
  }
  return names.size === 0
    ? undefined
    : `import { ${[...names].sort().join(", ")} } from "better-supabase";`;
}

interface CommentEntry {
  readonly id: number;
  readonly schema: string;
  readonly name: string;
  readonly comment: string | null;
}

/**
 * The catalog parts docs read: `GeneratorInput` satisfies it. Runtime callers
 * that only have `meta` (OpenAPI, MCP) pass none and get no docs.
 */
export interface DocsSource extends SchemaSource {
  readonly introspection?: {
    readonly tables: readonly CommentEntry[];
    readonly views: readonly CommentEntry[];
    readonly materializedViews?: readonly CommentEntry[];
    readonly columns: readonly {
      readonly table_id: number;
      readonly name: string;
      readonly comment: string | null;
      readonly check: string | null;
    }[];
  };
  readonly extras?: {
    readonly tables: readonly {
      readonly schema: string;
      readonly name: string;
      readonly checks: readonly { readonly definition: string }[];
    }[];
  };
}

export interface Bounds {
  readonly minimum?: number;
  readonly exclusiveMinimum?: number;
  readonly maximum?: number;
  readonly exclusiveMaximum?: number;
  readonly minLength?: number;
  readonly maxLength?: number;
}

/** What a column's comment and simple CHECK constraints say about it. */
export interface FieldDocs extends Bounds {
  readonly description?: string;
  readonly examples?: readonly unknown[];
}

export interface TableDocs {
  readonly title: string;
  readonly description?: string;
  /** By database column name. */
  readonly fields: ReadonlyMap<string, FieldDocs>;
}

const EXAMPLE = /^\s*@example\s+(.+?)\s*$/gm;

/**
 * Splits a comment into its description and `@example` lines. An example is
 * JSON (`@example 42`, `@example "KVK-1"`) or, when it doesn't parse, text.
 */
export function parseComment(comment: string | null): {
  readonly description?: string;
  readonly examples: readonly unknown[];
} {
  if (!comment) return { examples: [] };
  const examples = [...comment.matchAll(EXAMPLE)].map((match) => {
    const raw = match[1] ?? "";
    try {
      const parsed: unknown = JSON.parse(raw);
      return parsed;
    } catch {
      return raw;
    }
  });
  const description = comment.replace(EXAMPLE, "").trim();
  return description ? { description, examples } : { examples };
}

const COMPARISON =
  /^(?:(char_length|length)\(\(?"?(\w+)"?\)?(?:::[\w ]+)?\)|\(?"?(\w+)"?\)?(?:::[\w ]+)?)\s*(>=|>|<=|<)\s*\(?'?(-?\d+(?:\.\d+)?)'?\)?(?:::[\w ]+)?$/;
const REVERSED =
  /^\(?'?(-?\d+(?:\.\d+)?)'?\)?(?:::[\w ]+)?\s*(>=|>|<=|<)\s*(?:(char_length|length)\(\(?"?(\w+)"?\)?(?:::[\w ]+)?\)|\(?"?(\w+)"?\)?(?:::[\w ]+)?)$/;
const FLIP = { ">=": "<=", ">": "<", "<=": ">=", "<": ">" } as const;
type Operator = keyof typeof FLIP;

/** Drops parentheses that wrap the whole expression. */
function unwrap(expression: string): string {
  let text = expression.trim().replace(/^CHECK\s*/, "");
  while (text.startsWith("(") && text.endsWith(")")) {
    let depth = 0;
    let wraps = true;
    for (let i = 0; i < text.length - 1; i++) {
      if (text[i] === "(") depth++;
      else if (text[i] === ")") depth--;
      if (depth === 0) {
        wraps = false;
        break;
      }
    }
    if (!wraps) break;
    text = text.slice(1, -1).trim();
  }
  return text;
}

/** Terms of a top-level `AND` chain. */
function conjuncts(expression: string): string[] {
  const terms: string[] = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < expression.length; i++) {
    const char = expression[i];
    if (char === "(") depth++;
    else if (char === ")") depth--;
    else if (depth === 0 && expression.startsWith(" AND ", i)) {
      terms.push(expression.slice(start, i));
      start = i + 5;
    }
  }
  terms.push(expression.slice(start));
  return terms.map(unwrap);
}

interface Comparison {
  readonly column: string;
  readonly length: boolean;
  readonly operator: Operator;
  readonly value: number;
}

function comparison(term: string): Comparison | undefined {
  const forward = COMPARISON.exec(term);
  if (forward) {
    return {
      column: forward[2] ?? forward[3] ?? "",
      length: forward[1] !== undefined,
      // SAFETY: the regex only captures the four comparison operators.
      operator: forward[4] as Operator,
      value: Number(forward[5]),
    };
  }
  const reversed = REVERSED.exec(term);
  if (!reversed) return undefined;
  return {
    column: reversed[4] ?? reversed[5] ?? "",
    length: reversed[3] !== undefined,
    // SAFETY: the regex only captures the four comparison operators.
    operator: FLIP[reversed[2] as Operator],
    value: Number(reversed[1]),
  };
}

/**
 * Bounds from simple CHECK constraints, by column: `price >= 0`,
 * `rating between 1 and 5`, `char_length(name) <= 200`. Terms joined by
 * `OR`, functions other than `length` and `char_length`, and comparisons
 * between columns are left out.
 */
export function parseCheckBounds(
  definition: string,
): ReadonlyMap<string, Bounds> {
  const bounds = new Map<string, Bounds>();
  for (const term of conjuncts(unwrap(definition))) {
    if (/\sOR\s/i.test(term)) continue;
    const parsed = comparison(term);
    if (!parsed?.column || Number.isNaN(parsed.value)) continue;
    const current = bounds.get(parsed.column) ?? {};
    bounds.set(parsed.column, { ...current, ...boundOf(parsed) });
  }
  return bounds;
}

function boundOf({ length, operator, value }: Comparison): Bounds {
  if (length) {
    switch (operator) {
      case ">=":
        return { minLength: value };
      case ">":
        return { minLength: value + 1 };
      case "<=":
        return { maxLength: value };
      case "<":
        return { maxLength: value - 1 };
      default: {
        const exhaustive: never = operator;
        return exhaustive;
      }
    }
  }
  switch (operator) {
    case ">=":
      return { minimum: value };
    case ">":
      return { exclusiveMinimum: value };
    case "<=":
      return { maximum: value };
    case "<":
      return { exclusiveMaximum: value };
    default: {
      const exhaustive: never = operator;
      return exhaustive;
    }
  }
}

/** `customer_tags` → `Customer tags`. */
export function titleOf(name: string): string {
  const words = name.replaceAll("_", " ").trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

type Catalog = NonNullable<DocsSource["introspection"]>;

interface DocsIndex {
  readonly entries: ReadonlyMap<string, CommentEntry>;
  readonly columns: ReadonlyMap<number, Catalog["columns"][number][]>;
}

const docsIndexes = new WeakMap<Catalog, DocsIndex>();

type Extras = NonNullable<DocsSource["extras"]>;

const checkIndexes = new WeakMap<Extras, ReadonlyMap<string, string[]>>();

/** CHECK definitions by `schema.name`, built once per extras. */
function checksIndex(extras: Extras): ReadonlyMap<string, string[]> {
  let index = checkIndexes.get(extras);
  if (index) return index;
  const map = new Map<string, string[]>();
  for (const table of extras.tables) {
    const key = `${table.schema}.${table.name}`;
    map.set(key, [
      ...(map.get(key) ?? []),
      ...table.checks.map((check) => check.definition),
    ]);
  }
  index = map;
  checkIndexes.set(extras, index);
  return index;
}

/** The catalog keyed for `tableDocs`, built once per catalog. */
function docsIndex(catalog: Catalog): DocsIndex {
  let index = docsIndexes.get(catalog);
  if (index) return index;
  const entries = new Map<string, CommentEntry>();
  for (const item of [
    ...catalog.tables,
    ...catalog.views,
    ...(catalog.materializedViews ?? []),
  ]) {
    const key = `${item.schema}.${item.name}`;
    if (!entries.has(key)) entries.set(key, item);
  }
  const columns = new Map<number, Catalog["columns"][number][]>();
  for (const column of catalog.columns) {
    const list = columns.get(column.table_id);
    if (list) list.push(column);
    else columns.set(column.table_id, [column]);
  }
  index = { entries, columns };
  docsIndexes.set(catalog, index);
  return index;
}

/** Title, description and per-column docs, or `undefined` without a catalog. */
export function tableDocs(
  input: DocsSource,
  table: TableMeta,
): TableDocs | undefined {
  const catalog = input.introspection;
  if (!catalog) return undefined;
  const index = docsIndex(catalog);
  const entry = index.entries.get(`${table.schema}.${table.name}`);
  const checks = new Map<string, Bounds>();
  const addChecks = (definition: string): void => {
    for (const [column, bounds] of parseCheckBounds(definition))
      checks.set(column, { ...checks.get(column), ...bounds });
  };
  const extras = input.extras;
  for (const definition of extras
    ? (checksIndex(extras).get(`${table.schema}.${table.name}`) ?? [])
    : [])
    addChecks(definition);
  const fields = new Map<string, FieldDocs>();
  for (const column of entry ? (index.columns.get(entry.id) ?? []) : []) {
    if (column.check) addChecks(column.check);
    const { description, examples } = parseComment(column.comment);
    fields.set(column.name, {
      ...(description === undefined ? {} : { description }),
      ...(examples.length > 0 ? { examples } : {}),
    });
  }
  for (const [column, bounds] of checks)
    fields.set(column, { ...fields.get(column), ...bounds });
  const { description } = parseComment(entry?.comment ?? null);
  return {
    title: titleOf(table.name),
    ...(description === undefined ? {} : { description }),
    fields,
  };
}

/** A variant's title: `Customers`, `Customers insert`, `Customers update`. */
export function variantTitle(docs: TableDocs, variant: Variant): string {
  return variant === "Row"
    ? docs.title
    : `${docs.title} ${variant.toLowerCase()}`;
}

function exampleFits(scalar: ScalarKind, value: unknown): boolean {
  switch (scalar.kind) {
    case "uuid":
    case "string":
    case "datetime":
    case "date":
      return typeof value === "string";
    case "enum":
      return typeof value === "string" && scalar.values.includes(value);
    case "integer":
      return Number.isInteger(value);
    case "number":
      return typeof value === "number";
    case "boolean":
      return typeof value === "boolean";
    case "json":
    case "unknown":
      return true;
    case "instant":
    case "plainDateTime":
    case "bigint":
      return false;
    default: {
      const exhaustive: never = scalar;
      return exhaustive;
    }
  }
}

/**
 * The docs a field's validator can carry: value bounds on numbers, length
 * bounds on text, and only examples its type accepts.
 */
export function fieldDocs(
  docs: TableDocs | undefined,
  plan: FieldPlan,
): FieldDocs {
  const found = docs?.fields.get(plan.column.db);
  if (!found || plan.customJson || plan.column.storage !== undefined) return {};
  const numeric =
    !plan.column.array &&
    (plan.scalar.kind === "integer" || plan.scalar.kind === "number");
  const text = !plan.column.array && plan.scalar.kind === "string";
  const fits = (value: unknown): boolean =>
    (value === null && plan.nullable) ||
    (plan.column.array
      ? Array.isArray(value) &&
        value.every((item) => exampleFits(plan.scalar, item))
      : exampleFits(plan.scalar, value));
  const examples = found.examples?.filter(fits) ?? [];
  return {
    ...(found.description === undefined
      ? {}
      : { description: found.description }),
    ...(examples.length > 0 ? { examples } : {}),
    ...(numeric
      ? pick(found, [
          "minimum",
          "exclusiveMinimum",
          "maximum",
          "exclusiveMaximum",
        ])
      : {}),
    ...(text ? pick(found, ["minLength", "maxLength"]) : {}),
  };
}

function pick(bounds: Bounds, keys: readonly (keyof Bounds)[]): Bounds {
  const out: Record<string, number> = {};
  for (const key of keys) {
    const value = bounds[key];
    if (value !== undefined) out[key] = value;
  }
  return out;
}

export function optionalLine(line: string | undefined): string[] {
  return line === undefined ? [] : [line];
}

export function variantsFor(table: TableMeta): readonly Variant[] {
  if (table.kind !== "view") return ["Row", "Insert", "Update"];
  const columns = Object.values(table.columns).filter(
    (column) => !column.generated,
  );
  return [
    "Row",
    ...(columns.some((column) => column.insertable !== false)
      ? (["Insert"] as const)
      : []),
    ...(columns.some((column) => column.updatable !== false)
      ? (["Update"] as const)
      : []),
  ];
}

export function tableEntries(input: SchemaSource): [string, TableMeta][] {
  return Object.entries(input.meta.tables).sort(([a], [b]) =>
    a < b ? -1 : a > b ? 1 : 0,
  );
}

export function propertyKey(name: string): string {
  return /^[A-Za-z_$][\w$]*$/.test(name) ? name : JSON.stringify(name);
}

/** `customerTags` + `Insert` → `customerTagsInsert`. */
export function schemaName(table: string, variant: Variant): string {
  return `${table.replace(/^[A-Z]/, (c) => c.toLowerCase())}${variant}`;
}

/** Output path next to the main module: `generated.ts` → `generated.zod.ts`. */
export function siblingPath(output: string, suffix: string): string {
  return output.replace(/(\.[cm]?ts)?$/, `.${suffix}`);
}

export const HEADER =
  "// Generated by better-supabase. Do not edit; run `better-supabase gen`.\n";

/** `./metadata.ts#metadataSchema` → `{ from: './metadata.ts', name: 'metadataSchema' }`. */
export function parseImport(spec: string): { from: string; name: string } {
  const [from, name] = spec.split("#");
  if (!from || !name) throw new Error(`Expected "path#export", got "${spec}"`);
  return { from, name };
}
