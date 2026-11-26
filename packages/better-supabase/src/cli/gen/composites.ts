import type { ExtrasDomain, GeneratorMetadata } from "../../config/index.ts";
import type { ColumnMeta, FieldSpec } from "../../index.ts";

import { columnField, unmappedType } from "../../core/column-kind.ts";
import { parseCheckBounds } from "../../generators/index.ts";
import { parseCheckNotNull } from "./shared.ts";

export interface ResolvedColumnType {
  readonly type: string;
  readonly array: boolean;
  readonly notNull: boolean;
  readonly bounds?: Pick<
    ColumnMeta,
    | "minimum"
    | "exclusiveMinimum"
    | "maximum"
    | "exclusiveMaximum"
    | "minLength"
    | "maxLength"
  >;
  readonly fields?: Readonly<Record<string, ColumnMeta>>;
}

/**
 * The type validators use. A domain becomes its base type, and a NOT NULL
 * domain or a `VALUE IS NOT NULL` check makes the column not null. Simple CHECK
 * bounds (`VALUE >= 0`) are kept. Composite attributes are attached.
 */
/** Resolves a column and records it when the type stays unknown. */
export function columnResolution(
  column: {
    readonly name: string;
    readonly udt: string;
    readonly typeSchema: string;
    readonly isArray: boolean;
  },
  table: { readonly schema: string; readonly name: string },
  ctx: {
    readonly domains: ReadonlyMap<string, ExtrasDomain>;
    readonly introspection: { readonly types: readonly TypeEntry[] };
    readonly unmapped: string[];
  },
  hasValues: boolean,
): ResolvedColumnType {
  const resolved = resolveColumnType(
    column,
    ctx.domains.get(`${column.typeSchema}.${column.udt}`),
    ctx.introspection.types,
  );

  noteColumnType(
    ctx.unmapped,
    `${table.schema}.${table.name}.${column.name}`,
    resolved,
    hasValues,
  );

  return resolved;
}

export function resolveColumnType(
  column: {
    readonly name: string;
    readonly udt: string;
    readonly typeSchema: string;
    readonly isArray: boolean;
  },
  domain: ExtrasDomain | undefined,
  types: readonly TypeEntry[],
): ResolvedColumnType {
  let type = column.udt;
  let array = column.isArray;
  let notNull = false;
  let schema = column.typeSchema;
  let bounds: ResolvedColumnType["bounds"];

  if (domain) {
    notNull = domain.notNull;
    schema = domain.baseSchema;

    if (domain.baseType.startsWith("_")) {
      type = domain.baseType.slice(1);
      array = true;
    } else {
      type = domain.baseType;
    }

    const collected: ResolvedColumnType["bounds"] = {};

    for (const check of domain.checks ?? []) {
      const rewritten = check.replaceAll(/\bVALUE\b/gi, column.name);
      const parsed = parseCheckBounds(rewritten).get(column.name);

      if (parsed) {
        Object.assign(collected, parsed);
        bounds = collected;
      }

      if (parseCheckNotNull(rewritten).includes(column.name)) {
        notNull = true;
      }
    }
  }

  const fields = compositeFields(types, schema, type);

  return {
    type,
    array,
    notNull,
    ...(bounds ? { bounds } : {}),
    ...(fields ? { fields } : {}),
  };
}

type TypeEntry = GeneratorMetadata["types"][number];

/**
 * Attributes of a composite type, keyed by attribute name. Nested attributes
 * are nullable, because the catalog metadata does not record their nullability.
 * Returns nothing for enums, scalars and unknown names.
 */
export function compositeFields(
  types: readonly TypeEntry[],
  schema: string,
  name: string,
): Readonly<Record<string, ColumnMeta>> | undefined {
  const byId = new Map(types.map((type) => [type.id, type]));

  const found =
    types.find((type) => type.schema === schema && type.name === name) ??
    types.find((type) => type.name === name);

  if (!found || found.attributes.length === 0 || found.enums.length > 0) {
    return undefined;
  }

  return attributesOf(found, byId, new Set([found.id]));
}

function attributesOf(
  type: TypeEntry,
  byId: ReadonlyMap<number, TypeEntry>,
  seen: ReadonlySet<number>,
): Readonly<Record<string, ColumnMeta>> {
  const fields: Record<string, ColumnMeta> = {};

  for (const attribute of type.attributes) {
    fields[attribute.name] = attributeMeta(
      attribute.name,
      byId.get(attribute.type_id),
      byId,
      seen,
    );
  }

  return fields;
}

function attributeMeta(
  name: string,
  type: TypeEntry | undefined,
  byId: ReadonlyMap<number, TypeEntry>,
  seen: ReadonlySet<number>,
): ColumnMeta {
  if (!type || seen.has(type.id)) {
    return { db: name, type: type?.name ?? "unknown", nullable: true };
  }

  const array = type.name.startsWith("_");
  const elementName = array ? type.name.slice(1) : type.name;

  const element = array
    ? ([...byId.values()].find(
        (entry) => entry.name === elementName && entry.schema === type.schema,
      ) ?? type)
    : type;

  if (
    element.attributes.length > 0 &&
    element.enums.length === 0 &&
    !seen.has(element.id)
  ) {
    return {
      db: name,
      type: elementName,
      nullable: true,
      ...(array ? { array: true } : {}),
      fields: attributesOf(element, byId, new Set([...seen, element.id])),
    };
  }

  return {
    db: name,
    type: elementName,
    nullable: true,
    ...(array ? { array: true } : {}),
    ...(element.enums.length > 0 ? { enum: [...element.enums] } : {}),
    ...(elementName === "json" || elementName === "jsonb"
      ? { json: true }
      : {}),
  };
}

/** Appends the unknown-type notice when any column stayed unmapped. */
export function recordUnmapped(
  columns: readonly string[],
  notices: string[],
): void {
  const notice = unmappedNotice(columns);

  if (notice !== undefined) {
    notices.push(notice);
  }
}

/** The notice `gen` prints when a column type stays unknown. */
function unmappedNotice(columns: readonly string[]): string | undefined {
  if (columns.length === 0) {
    return undefined;
  }

  return `gen left these column types unknown: ${columns.join(", ")}. Map them in gen.json, or name the column in standardSchema({ json }).`;
}

/** Field specs for a composite or `returns table` result. */
export function columnFields(
  fields: Readonly<Record<string, ColumnMeta>>,
): Record<string, FieldSpec> {
  return Object.fromEntries(
    Object.entries(fields).map(([name, column]) => [name, columnField(column)]),
  );
}

/** Domains keyed by `schema.name`, the lookup a column's type uses. */
export function domainIndex(
  domains: readonly ExtrasDomain[] | undefined,
): Map<string, ExtrasDomain> {
  return new Map(
    (domains ?? []).map((domain) => [
      `${domain.schema}.${domain.name}`,
      domain,
    ]),
  );
}

/**
 * Records a column whose type `gen` cannot map. A CHECK union is mapped (it is
 * an enum), and so are `record` and `void`.
 */
export function noteColumnType(
  unmapped: string[],
  path: string,
  resolved: ResolvedColumnType,
  hasValues: boolean,
): void {
  if (resolved.fields) {
    noteUnmappedFields(unmapped, path, resolved.fields);

    return;
  }

  if (!hasValues && unmappedType(resolved.type)) {
    unmapped.push(`${path} (${resolved.type})`);
  }
}

function noteUnmappedFields(
  unmapped: string[],
  path: string,
  fields: Readonly<Record<string, ColumnMeta>>,
): void {
  for (const [name, field] of Object.entries(fields)) {
    const next = `${path}.${name}`;

    if (field.fields) {
      noteUnmappedFields(unmapped, next, field.fields);
    } else if (unmappedType(field.type)) {
      unmapped.push(`${next} (${field.type})`);
    }
  }
}
