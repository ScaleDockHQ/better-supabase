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
        column.json && input.config.json[`${table.name}.${column.db}`],
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

export function optionalLine(line: string | undefined): string[] {
  return line === undefined ? [] : [line];
}

export function variantsFor(table: TableMeta): readonly Variant[] {
  return table.kind === "view" ? ["Row"] : ["Row", "Insert", "Update"];
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
