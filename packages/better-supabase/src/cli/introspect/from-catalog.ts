import type { GeneratorMetadata } from "./typegen.ts";
import type {
  Catalog,
  CatalogColumn,
  CatalogFunction,
  CatalogTable,
  Snapshot,
} from "./types.ts";

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

/**
 * Builds a snapshot from catalog records: the inverse of `toCatalog`. Tests
 * and benchmarks describe schemas as tables and functions; this produces the
 * typegen metadata and extras those records imply.
 */
export function fromCatalog(catalog: Catalog): Snapshot {
  const schemas = [
    ...new Set([
      ...catalog.schemas,
      ...catalog.tables.map((table) => table.schema),
    ]),
  ].sort();
  const meta: Mutable<GeneratorMetadata> = {
    version: 1,
    schemas: schemas.map((name, index) => ({
      id: 4_000_000 + index,
      name,
      owner: "postgres",
    })),
    tables: [],
    foreignTables: [],
    views: [],
    materializedViews: [],
    columns: [],
    primaryKeys: [],
    relationships: [],
    functions: [],
    types: [],
  };

  const typeIds = new Map<string, number>();
  const typeId = (schema: string, name: string): number => {
    const key = `${schema}.${name}`;
    let id = typeIds.get(key);
    if (id === undefined) {
      id = 2_000_000 + typeIds.size;
      typeIds.set(key, id);
      meta.types.push({
        id,
        name,
        schema,
        format: name,
        enums: [],
        attributes: [],
        comment: null,
        type_relation_id: null,
      });
    }
    return id;
  };
  const enums = new Map(
    catalog.enums.map((entry) => [`${entry.schema}.${entry.name}`, entry]),
  );
  for (const entry of catalog.enums) {
    const id = typeId(entry.schema, entry.name);
    const type = meta.types.find((candidate) => candidate.id === id)!;
    type.enums = [...entry.values];
  }

  const column = (
    table: CatalogTable,
    id: number,
    entry: CatalogColumn,
    index: number,
  ): GeneratorMetadata["columns"][number] => ({
    table_id: id,
    schema: table.schema,
    table: table.name,
    id: `${id}.${index + 1}`,
    ordinal_position: index + 1,
    name: entry.name,
    default_value: entry.default,
    data_type: entry.isArray
      ? "ARRAY"
      : entry.isEnum
        ? "USER-DEFINED"
        : entry.udt,
    format: entry.format,
    type_schema: entry.typeSchema,
    is_identity: entry.identity !== null,
    identity_generation:
      entry.identity === "always"
        ? "ALWAYS"
        : entry.identity === "by default"
          ? "BY DEFAULT"
          : null,
    is_generated: entry.generated,
    is_nullable: entry.nullable,
    is_updatable: entry.updatable,
    is_unique: false,
    enums: entry.isEnum
      ? [...(enums.get(`${entry.typeSchema}.${entry.udt}`)?.values ?? [])]
      : [],
    check: null,
    comment: entry.comment,
  });

  catalog.tables.forEach((table, index) => {
    const id = table.id || 1_000_000 + index;
    if (table.kind === "table") {
      meta.tables.push({
        id,
        schema: table.schema,
        name: table.name,
        rls_enabled: table.rls,
        rls_forced: table.forceRls,
        replica_identity: table.replicaIdentity ?? "DEFAULT",
        bytes: 0,
        size: "0 bytes",
        live_rows_estimate: 0,
        dead_rows_estimate: 0,
        comment: table.comment,
      });
    } else {
      meta.views.push({
        id,
        schema: table.schema,
        name: table.name,
        is_updatable: table.insertable || table.updatable,
        is_insert_enabled: table.insertable,
        is_update_enabled: table.updatable,
        comment: table.comment,
      });
    }
    table.columns.forEach((entry, position) =>
      meta.columns.push(column(table, id, entry, position)),
    );
    for (const name of table.primaryKey) {
      meta.primaryKeys.push({
        schema: table.schema,
        table_name: table.name,
        name,
        table_id: id,
      });
    }
    for (const fk of table.foreignKeys) {
      meta.relationships.push({
        foreign_key_name: fk.name,
        schema: table.schema,
        relation: table.name,
        columns: [...fk.columns],
        is_one_to_one: fk.oneToOne,
        referenced_schema: fk.refSchema,
        referenced_relation: fk.refTable,
        referenced_columns: [...fk.refColumns],
      });
    }
  });

  const relationIds = new Map(
    [...meta.tables, ...meta.views].map((entry) => [
      `${entry.schema}.${entry.name}`,
      entry.id,
    ]),
  );
  const argType = (schema: string, udt: string): number =>
    typeId(enums.has(`${schema}.${udt}`) ? schema : "pg_catalog", udt);
  catalog.functions.forEach((fn: CatalogFunction, index) => {
    const args: GeneratorMetadata["functions"][number]["args"] = [
      ...fn.args.map((arg) => ({
        mode: "in" as const,
        name: arg.name,
        type_id: argType(fn.schema, arg.isArray ? `_${arg.udt}` : arg.udt),
        has_default: arg.hasDefault,
      })),
      ...(fn.returnsTable ?? []).map((entry) => ({
        mode: "table" as const,
        name: entry.name,
        type_id: argType(fn.schema, entry.udt),
        has_default: false,
      })),
    ];
    meta.functions.push({
      id: 3_000_000 + index,
      schema: fn.schema,
      name: fn.name,
      language: fn.language,
      definition: "",
      complete_statement: "",
      args,
      argument_types: fn.signature,
      identity_argument_types: fn.signature,
      return_type_id: fn.returnsRelation
        ? typeId(fn.returnsRelation.split(".")[0]!, fn.returns)
        : argType(fn.schema, fn.returns),
      return_type: fn.returns,
      return_type_relation_id: fn.returnsRelation
        ? (relationIds.get(fn.returnsRelation) ?? null)
        : null,
      is_set_returning_function: fn.returnsSet,
      prorows: null,
      behavior: fn.volatility.toUpperCase() as "IMMUTABLE",
      security_definer: fn.securityDefiner,
      config_params:
        fn.searchPath === null
          ? null
          : { search_path: fn.searchPath === "" ? '""' : fn.searchPath },
    });
  });

  return {
    version: 2,
    schemas,
    generator: meta,
    extras: {
      tables: catalog.tables.map((table, index) => ({
        id: table.id || 1_000_000 + index,
        schema: table.schema,
        name: table.name,
        primaryKey: table.primaryKey,
        uniques: table.uniques,
        foreignKeys: table.foreignKeys.map((fk) => ({
          name: fk.name,
          onDelete: fk.onDelete,
          onUpdate: fk.onUpdate,
        })),
        checks: table.checks,
        indexes: table.indexes,
        policies: table.policies,
        triggers: table.triggers,
        grants: table.grants,
      })),
      buckets: catalog.buckets,
      realtime: catalog.realtime,
    },
  };
}
