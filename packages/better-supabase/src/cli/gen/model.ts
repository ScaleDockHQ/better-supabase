import type { GeneratorModel, ResolvedConfig } from "../../config/index.ts";
import type {
  Casing,
  ClaimsMeta,
  Codec,
  ColumnMeta,
  FunctionMeta,
  FunctionResult,
  RealtimeTableMeta,
  RelationMeta,
  SchemaMeta,
  TableMeta,
} from "../../index.ts";
import type {
  Catalog,
  CatalogColumn,
  CatalogTable,
  Snapshot,
} from "../introspect/types.ts";

import { DEFAULT_CLAIMS, tenantClaimPaths } from "../../config/index.ts";
import { toCamel, toSnake } from "../../index.ts";
import { toCatalog } from "../introspect/catalog.ts";
import {
  type GeneratorMetadata,
  restrictSchemas,
  tsTypeOf,
} from "../introspect/typegen.ts";
import {
  arrayOf,
  isJsonUdt,
  parseCheckNotNull,
  parseCheckUnion,
  sameColumns,
  singular,
} from "./shared.ts";

const SOFT_DELETE_UDTS = new Set(["timestamptz", "timestamp"]);

const applyCasing = (name: string, casing: Casing): string =>
  casing === "camel" ? toCamel(name) : name;

export interface ColumnModel {
  readonly app: string;
  readonly db: string;
  readonly snapshot: CatalogColumn;
  /** TypeScript type without `| null`. */
  readonly tsType: string;
  readonly nullable: boolean;
  /** Optional on insert. */
  readonly optional: boolean;
  /** An insert may leave it out: a default, `insertOptional`, or a CHECK-narrowed column a `before insert` trigger can fill. */
  readonly filled: boolean;
  /** Not writable (generated always / identity always). */
  readonly readonly: boolean;
  readonly values: readonly string[] | undefined;
  readonly json: boolean;
  readonly codec: Codec | undefined;
  /** Bucket id from `config.storagePaths`. */
  readonly storage: string | undefined;
  readonly insertable: boolean;
  readonly updatable: boolean;
}

interface RelationModel {
  readonly name: string;
  readonly meta: RelationMeta;
}

interface TableModel {
  readonly key: string;
  readonly snapshot: CatalogTable;
  readonly casing: Casing;
  readonly columns: readonly ColumnModel[];
  readonly relations: readonly RelationModel[];
  readonly meta: TableMeta;
}

interface EnumModel {
  readonly schema: string;
  readonly name: string;
  /** Constant name for the value array, e.g. `noteKindValues`. */
  readonly constant: string;
  readonly values: readonly string[];
}

export interface FunctionModel {
  readonly key: string;
  readonly meta: FunctionMeta;
  readonly args: readonly { name: string; tsType: string; optional: boolean }[];
  readonly returns: string;
}

interface JsonImport {
  readonly name: string;
  /** Path relative to the project root, without the `#Name` part. */
  readonly from: string;
}

export interface Model {
  readonly tables: readonly TableModel[];
  readonly enums: readonly EnumModel[];
  readonly functions: readonly FunctionModel[];
  readonly jsonImports: readonly JsonImport[];
  readonly meta: SchemaMeta;
  readonly config: ResolvedConfig;
  readonly catalog: Catalog;
  /** Typegen metadata restricted to the configured schemas. */
  readonly introspection: GeneratorMetadata;
  /** Config entries that matched nothing in the schema. */
  readonly warnings: readonly string[];
}

function tableKey(
  table: CatalogTable,
  casing: Casing,
  schemas: readonly string[],
): string {
  const base = applyCasing(table.name, casing);
  if (schemas.length === 1 || table.schema === "public") return base;
  return applyCasing(`${table.schema}_${table.name}`, casing);
}

const CODEC_TYPE: Record<Codec, string> = {
  instant: "Temporal.Instant",
  plainDateTime: "Temporal.PlainDateTime",
  bigint: "bigint",
  string: "string",
};

function codecFor(udt: string, config: ResolvedConfig): Codec | undefined {
  const { codecs } = config;
  if (codecs.timestamptz === "instant") {
    if (udt === "timestamptz") return "instant";
    if (udt === "timestamp") return "plainDateTime";
  }
  if (udt === "int8" && codecs.int8 !== "number") return codecs.int8;
  if (udt === "numeric" && codecs.numeric === "string") return "string";
  return undefined;
}

const TEXT_UDTS = new Set(["text", "varchar", "bpchar"]);

/** `config.storagePaths` resolved to bucket ids, with a check that every key is used. */
function storagePathsOf(config: ResolvedConfig) {
  const bucketId = (name: string): string => {
    const bucket = config.buckets[name];
    if (!bucket) return name;
    return (
      bucket.id ?? name.replaceAll(/[A-Z]/g, (char) => `-${char.toLowerCase()}`)
    );
  };
  const unused = new Set(Object.keys(config.storagePaths));
  return {
    lookup(schema: string, table: string, column: string, udt: string) {
      const key = [`${schema}.${table}.${column}`, `${table}.${column}`].find(
        (candidate) => candidate in config.storagePaths,
      );
      if (key === undefined) return;
      unused.delete(key);
      if (!TEXT_UDTS.has(udt)) {
        throw new TypeError(
          `storagePaths["${key}"]: ${schema}.${table}.${column} is ${udt}, not a text column`,
        );
      }
      // SAFETY: the check above found this key in storagePaths, whose values are strings.
      return bucketId(config.storagePaths[key]!);
    },
    assertUsed(): void {
      const [first] = unused;
      if (first !== undefined) {
        throw new TypeError(
          `storagePaths["${first}"]: no such column. Use \`table.column\` or \`schema.table.column\` (database names) in \`schemas\`.`,
        );
      }
    },
  };
}

function enumType(values: readonly string[]): string {
  return values.map((value) => JSON.stringify(value)).join(" | ");
}

/** Builds the codegen model from a snapshot and config. */
export function buildModel(snapshot: Snapshot, config: ResolvedConfig): Model {
  const catalog = toCatalog(snapshot);
  const introspection = restrictSchemas(snapshot.generator, config.schemas);
  const tsType = (schema: string, format: string, typeSchema?: string) =>
    tsTypeOf(introspection, schema, format, typeSchema).replaceAll(
      /\(([\w.$]+)\)\[\]/g,
      "$1[]",
    );
  const enumsByName = new Map<string, readonly string[]>();
  for (const entry of catalog.enums) {
    enumsByName.set(`${entry.schema}.${entry.name}`, entry.values);
  }

  const jsonImports = new Map<string, JsonImport>();
  const unusedJson = new Set(Object.keys(config.json));
  const jsonTypeFor = (table: string, column: string): string | undefined => {
    const override = config.json[`${table}.${column}`];
    if (!override) return undefined;
    unusedJson.delete(`${table}.${column}`);
    if ("type" in override) return override.type;
    const [from, name] = override.import.split("#");
    if (!from || !name) {
      throw new TypeError(
        `json["${table}.${column}"].import must look like "./path.ts#TypeName"`,
      );
    }
    jsonImports.set(name, { name, from });
    return name;
  };

  const storagePaths = storagePathsOf(config);
  const included = catalog.tables.filter(
    (table) =>
      config.schemas.includes(table.schema) &&
      !config.tables[table.name]?.exclude,
  );

  const keyOf = new Map<string, string>();
  for (const table of included) {
    keyOf.set(
      `${table.schema}.${table.name}`,
      tableKey(table, config.casing, config.schemas),
    );
  }

  const tables = included.map((table) => {
    const casing = config.tables[table.name]?.casing ?? config.casing;
    const checks = new Map<string, string[]>();
    const checkedNotNull = new Set<string>();
    for (const check of table.checks) {
      const union = parseCheckUnion(check.definition);
      if (union) checks.set(union.column, union.values);
      for (const column of parseCheckNotNull(check.definition))
        checkedNotNull.add(column);
    }
    const beforeInsert = table.triggers.some(
      (trigger) =>
        trigger.timing === "before" &&
        trigger.level === "row" &&
        trigger.events.includes("insert"),
    );
    const insertOptional = new Set(
      config.tables[table.name]?.insertOptional ?? [],
    );
    for (const name of insertOptional) {
      if (!table.columns.some((column) => column.name === name))
        throw new TypeError(
          `tables.${table.name}.insertOptional: "${name}" is not a column of ${table.schema}.${table.name}`,
        );
    }
    const columns = table.columns.map((column): ColumnModel => {
      const enumValues = column.isEnum
        ? enumsByName.get(`${column.typeSchema}.${column.udt}`)
        : undefined;
      const values = enumValues ?? checks.get(column.name);
      const json = isJsonUdt(column.udt);
      const override = json ? jsonTypeFor(table.name, column.name) : undefined;
      const storage = storagePaths.lookup(
        table.schema,
        table.name,
        column.name,
        column.udt,
      );
      const codec =
        override || values || storage
          ? undefined
          : codecFor(column.udt, config);
      const base =
        override ??
        (values
          ? enumType(values)
          : storage
            ? `StoragePath<${JSON.stringify(storage)}>`
            : codec
              ? CODEC_TYPE[codec]
              : undefined);
      const columnType =
        base === undefined
          ? tsType(table.schema, column.format, column.typeSchema)
          : column.isArray
            ? arrayOf(base)
            : base;
      const readonly = column.generated || column.identity === "always";
      const narrowed = column.nullable && checkedNotNull.has(column.name);
      const nullable = column.nullable && !narrowed;
      const filled =
        column.hasDefault ||
        insertOptional.has(column.name) ||
        (narrowed && beforeInsert);
      const insertable = !readonly && table.insertable;
      const updatable = !readonly && table.updatable && column.updatable;
      return {
        app: applyCasing(column.name, casing),
        db: column.name,
        snapshot: column,
        tsType: columnType,
        nullable,
        filled,
        optional: nullable || filled || readonly,
        readonly,
        values,
        json,
        codec,
        storage,
        insertable,
        updatable,
      };
    });
    return { table, casing, columns };
  });
  storagePaths.assertUsed();
  const known = new Set(
    catalog.tables
      .filter((table) => config.schemas.includes(table.schema))
      .map((table) => table.name),
  );
  const warnings = [
    ...Object.keys(config.tables)
      .filter((name) => !known.has(name))
      .map(
        (name) =>
          `tables["${name}"]: no table by that name in ${config.schemas.join(", ")}, so the entry does nothing.`,
      ),
    ...[...unusedJson].map(
      (key) =>
        `json["${key}"]: no json or jsonb column by that name, so the type is not used. Keys are \`table.column\` with database names.`,
    ),
  ];

  const byKey = new Map<string, (typeof tables)[number]>();
  for (const entry of tables) {
    byKey.set(`${entry.table.schema}.${entry.table.name}`, entry);
  }
  const appName = (schema: string, table: string, column: string): string => {
    const entry = byKey.get(`${schema}.${table}`);
    return entry?.columns.find((col) => col.db === column)?.app ?? column;
  };

  // Relations: forward from each FK, reverse on the referenced table.
  const relations = new Map<string, RelationModel[]>();
  const push = (tableId: string, relation: RelationModel): void => {
    const list = relations.get(tableId);
    if (list) list.push(relation);
    else relations.set(tableId, [relation]);
  };

  for (const { table, casing, columns } of tables) {
    const sourceId = `${table.schema}.${table.name}`;
    for (const fk of table.foreignKeys) {
      const targetId = `${fk.refSchema}.${fk.refTable}`;
      const target = byKey.get(targetId);
      if (!target) continue;
      const targetKey = keyOf.get(targetId) ?? fk.refTable;

      const sourceColumns = fk.columns.map((column) =>
        appName(table.schema, table.name, column),
      );
      const targetColumns = fk.refColumns.map((column) =>
        appName(fk.refSchema, fk.refTable, column),
      );
      const nullable =
        (config.relations.nullableUnderRls && target.table.rls) ||
        fk.columns.some(
          (column) =>
            columns.find((col) => col.db === column)?.nullable ?? true,
        );
      const onDelete =
        fk.onDelete === "cascade" ||
        fk.onDelete === "set null" ||
        fk.onDelete === "set default"
          ? { onDelete: fk.onDelete }
          : {};
      const naming = namingColumns(fk.columns, fk.refColumns);
      const [only] = naming;
      const forwardBase =
        naming.length === 1 && only?.endsWith("_id")
          ? only.slice(0, -3)
          : singular(fk.refTable);
      push(sourceId, {
        name: applyCasing(forwardBase, casing),
        meta: {
          table: targetKey,
          kind: "one",
          nullable,
          foreignKey: fk.name,
          columns: sourceColumns,
          references: targetColumns,
          direction: "forward",
          ...onDelete,
        },
      });

      const unique =
        fk.oneToOne ||
        sameColumns(table.primaryKey, fk.columns) ||
        table.uniques.some((key) => sameColumns(key.columns, fk.columns));
      push(targetId, {
        name: applyCasing(
          unique ? singular(table.name) : table.name,
          target.casing,
        ),
        meta: {
          table: keyOf.get(sourceId) ?? table.name,
          kind: unique ? "one" : "many",
          nullable: true,
          foreignKey: fk.name,
          columns: targetColumns,
          references: sourceColumns,
          direction: "reverse",
          ...onDelete,
        },
      });
    }
  }

  const flagsConfig = config.plugins;
  const tableModels: TableModel[] = tables.map(({ table, casing, columns }) => {
    const id = `${table.schema}.${table.name}`;
    const renames = config.tables[table.name]?.relations ?? {};
    const columnNames = new Set(columns.map((column) => column.app));
    const list = dedupeRelations(
      relations.get(id) ?? [],
      columnNames,
      casing,
    ).map((relation) => ({
      ...relation,
      name: renames[relation.name] ?? relation.name,
    }));

    const has = (db: string): string | undefined =>
      columns.find((col) => col.db === db)?.app;
    const flags: {
      softDelete?: string;
      timestamps?: { createdAt?: string; updatedAt?: string };
      tenant?: string;
      actor?: {
        createdBy?: string;
        updatedBy?: string;
        impersonatedBy?: string;
      };
    } = {};
    if (flagsConfig.softDelete) {
      const db = flagsConfig.softDelete.column;
      const column = columns.find((col) => col.db === db);
      if (column) {
        const udt = column.snapshot.udt;
        if (column.snapshot.isArray || !SOFT_DELETE_UDTS.has(udt)) {
          throw new TypeError(
            `plugins.softDelete.column: ${table.schema}.${table.name}.${db} is ${udt}, but softDelete() writes a timestamp. Use timestamptz or timestamp.`,
          );
        }
        flags.softDelete = column.app;
      }
    }
    if (flagsConfig.timestamps) {
      const createdAt = has(flagsConfig.timestamps.createdAt);
      const updatedAt = has(flagsConfig.timestamps.updatedAt);
      if (createdAt || updatedAt) {
        flags.timestamps = {
          ...(createdAt ? { createdAt } : {}),
          ...(updatedAt ? { updatedAt } : {}),
        };
      }
    }
    if (flagsConfig.tenant) {
      const column = has(flagsConfig.tenant.column);
      if (column) flags.tenant = column;
    }
    if (flagsConfig.actor) {
      const createdBy = has(flagsConfig.actor.createdBy);
      const updatedBy = has(flagsConfig.actor.updatedBy);
      const impersonatedBy = has(flagsConfig.actor.impersonatedBy);
      if (createdBy || updatedBy || impersonatedBy) {
        flags.actor = {
          ...(createdBy ? { createdBy } : {}),
          ...(updatedBy ? { updatedBy } : {}),
          ...(impersonatedBy ? { impersonatedBy } : {}),
        };
      }
    }

    const key = keyOf.get(id) ?? table.name;
    const columnMeta: Record<string, ColumnMeta> = {};
    for (const column of columns) {
      const meta: {
        -readonly [K in keyof ColumnMeta]: ColumnMeta[K];
      } = {
        db: column.db,
        type: column.snapshot.udt,
        nullable: column.nullable,
        hasDefault: column.filled,
      };
      if (column.readonly) meta.generated = true;
      if (column.snapshot.identity) meta.identity = column.snapshot.identity;
      if (!column.readonly && !column.insertable) meta.insertable = false;
      if (!column.readonly && !column.updatable) meta.updatable = false;
      if (column.snapshot.isArray) meta.array = true;
      if (column.json) meta.json = true;
      if (column.values) meta.enum = column.values;
      if (column.codec) meta.codec = column.codec;
      if (column.storage) meta.storage = column.storage;
      if (
        config.sensitive.includes(`${table.name}.${column.db}`) ||
        config.sensitive.includes(`${table.schema}.${table.name}.${column.db}`)
      )
        meta.sensitive = true;
      columnMeta[column.app] = meta;
    }
    const app = (db: string): string =>
      columns.find((col) => col.db === db)?.app ?? db;
    const uniqueKeys: Record<string, readonly string[]> = {};
    for (const unique of table.uniques)
      uniqueKeys[unique.name] = unique.columns.map(app);
    const relationMeta: Record<string, RelationMeta> = {};
    for (const relation of list) relationMeta[relation.name] = relation.meta;

    return {
      key,
      snapshot: table,
      casing,
      columns,
      relations: list,
      meta: {
        key,
        name: table.name,
        schema: table.schema,
        kind: table.kind,
        columns: columnMeta,
        primaryKey: table.primaryKey.map(app),
        uniqueKeys,
        relations: relationMeta,
        flags: flags,
      },
    };
  });

  const enums: EnumModel[] = catalog.enums
    .filter((entry) => config.schemas.includes(entry.schema))
    .map((entry) => ({
      schema: entry.schema,
      name: entry.name,
      constant: `${toCamel(entry.name)}Values`,
      values: entry.values,
    }));

  const tablesByName = new Map(
    tableModels.map((table) => [
      `${table.snapshot.schema}.${table.snapshot.name}`,
      table,
    ]),
  );
  const seen = new Set<string>();
  const functions: FunctionModel[] = catalog.functions
    .filter((fn) => config.schemas.includes(fn.schema))
    .filter((fn) => fn.returns !== "trigger" && fn.returns !== "event_trigger")
    .filter((fn) => !fn.args.some((arg) => arg.udt === "internal"))
    .filter((fn) => {
      // Overloads share one entry; the first signature wins.
      if (seen.has(fn.name)) return false;
      seen.add(fn.name);
      return true;
    })
    .map((fn) => {
      const typeOf = (format: string): string => {
        const isArray = format.startsWith("_");
        const values = enumsByName.get(
          `${fn.schema}.${isArray ? format.slice(1) : format}`,
        );
        if (values)
          return isArray ? arrayOf(enumType(values)) : enumType(values);
        return tsType(fn.schema, format);
      };
      let returns: string;
      let result: FunctionResult | undefined;
      const rowTable = fn.returnsRelation
        ? tablesByName.get(fn.returnsRelation)
        : undefined;
      if (fn.returnsTable) {
        const columns = fn.returnsTable.map((column) => {
          const codec = codecFor(column.udt, config);
          return {
            db: column.name,
            app: applyCasing(column.name, config.casing),
            codec,
            tsType: codec ? CODEC_TYPE[codec] : typeOf(column.udt),
          };
        });
        returns = `{ ${columns
          .map((column) => `${JSON.stringify(column.app)}: ${column.tsType}`)
          .join("; ")} }[]`;
        if (
          columns.some(
            (column) => column.codec !== undefined || column.app !== column.db,
          )
        ) {
          result = {
            columns: columns.map(({ db, app, codec }) => ({
              db,
              ...(app === db ? {} : { name: app }),
              ...(codec ? { codec } : {}),
            })),
          };
        }
      } else if (rowTable) {
        returns = `Models[${JSON.stringify(rowTable.key)}]['Row']`;
        if (fn.returnsSet) returns = arrayOf(returns);
        if (
          rowTable.columns.some(
            (column) => column.codec !== undefined || column.app !== column.db,
          )
        ) {
          result = { table: rowTable.key };
        }
      } else {
        returns = typeOf(fn.returns);
        if (fn.returnsSet) returns = arrayOf(returns);
      }
      return {
        key: fn.name,
        meta: {
          name: fn.name,
          schema: fn.schema,
          args: fn.args.map((arg) => ({ name: arg.name, type: arg.udt })),
          returns: fn.returns,
          returnsSet: fn.returnsSet,
          volatility: fn.volatility,
          ...(result ? { result } : {}),
        },
        args: fn.args.map((arg) => ({
          name: arg.name,
          tsType: typeOf(arg.isArray ? `_${arg.udt}` : arg.udt),
          optional: arg.hasDefault,
        })),
        returns,
      };
    });

  const tablesMeta: Record<string, TableMeta> = {};
  for (const table of tableModels) tablesMeta[table.key] = table.meta;
  const enumsMeta: Record<string, readonly string[]> = {};
  for (const entry of enums) enumsMeta[entry.name] = entry.values;
  const functionsMeta: Record<string, FunctionMeta> = {};
  for (const fn of functions) functionsMeta[fn.key] = fn.meta;

  const claimOverrides: Partial<Record<keyof ClaimsMeta, string>> = {};
  // SAFETY: DEFAULT_CLAIMS has one entry per ClaimsMeta key, and Object.keys
  // widens the keys to string.
  for (const key of Object.keys(DEFAULT_CLAIMS) as (keyof ClaimsMeta)[]) {
    if (config.claims[key] !== DEFAULT_CLAIMS[key]) {
      claimOverrides[key] = config.claims[key];
    }
  }
  const tenantClaim =
    config.claims.tenant === DEFAULT_CLAIMS.tenant
      ? undefined
      : tenantClaimPaths(config.claims.tenant);

  const meta: SchemaMeta = {
    version: 1,
    casing: config.casing,
    tables: tablesMeta,
    enums: enumsMeta,
    functions: functionsMeta,
    ...(Object.keys(config.buckets).length > 0
      ? {
          buckets: Object.fromEntries(
            Object.entries(config.buckets).map(([name, bucket]) => [
              name,
              {
                id:
                  bucket.id ??
                  name.replaceAll(/[A-Z]/g, (char) => `-${char.toLowerCase()}`),
                public: bucket.public ?? false,
                path: bucket.path,
                ...(bucket.policy ? { policy: bucket.policy } : {}),
                ...(bucket.policy === "tenant" && tenantClaim
                  ? { tenant: { claim: tenantClaim } }
                  : {}),
                ...(bucket.fileSizeLimit
                  ? { fileSizeLimit: bucket.fileSizeLimit }
                  : {}),
                ...(bucket.allowedMimeTypes
                  ? { allowedMimeTypes: bucket.allowedMimeTypes }
                  : {}),
              },
            ]),
          ),
        }
      : {}),
    ...(Object.keys(config.topics).length > 0 ? { topics: config.topics } : {}),
    ...(config.realtime.tables.length > 0
      ? { realtime: realtimeMeta(config.realtime.tables, tableModels) }
      : {}),
    ...(Object.keys(claimOverrides).length > 0
      ? { claims: claimOverrides }
      : {}),
  };

  return {
    tables: tableModels,
    enums,
    functions,
    jsonImports: [...jsonImports.values()],
    meta,
    config,
    catalog,
    introspection,
    warnings,
  };
}

function deepFreeze<T>(value: T): T {
  if (typeof value === "object" && value !== null && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const entry of Object.values(value)) deepFreeze(entry);
  }
  return value;
}

/** The public, frozen view of the model that generators receive. */
export function generatorModel(model: Model): GeneratorModel {
  return deepFreeze({
    tables: model.tables.map((table) => ({
      key: table.key,
      schema: table.snapshot.schema,
      name: table.snapshot.name,
      casing: table.casing,
      columns: table.columns.map((column) => ({
        app: column.app,
        db: column.db,
        tsType: column.tsType,
        nullable: column.nullable,
        optional: column.optional,
        readonly: column.readonly,
        values: column.values === undefined ? undefined : [...column.values],
        json: column.json,
      })),
    })),
    enums: model.enums.map((entry) => ({
      schema: entry.schema,
      name: entry.name,
      values: [...entry.values],
    })),
  });
}

/**
 * The columns that name a relation. A composite key that repeats a column on
 * both sides, such as `(customer_id, organization_id)` referencing
 * `(id, organization_id)` to keep rows in one tenant, is named by the rest.
 */
function namingColumns(
  columns: readonly string[],
  references: readonly string[],
): readonly string[] {
  const own = columns.filter((column, index) => column !== references[index]);
  return own.length > 0 ? own : columns;
}

/**
 * Makes relation names unique per table and distinct from column names:
 * two FKs to the same table become `customersByPrimaryContact`-style names.
 * When those still collide, the names use every column of the key
 * (`locationsByCustomerOrganization`), then the constraint name, and only
 * then a trailing `_`.
 */
function dedupeRelations(
  list: readonly RelationModel[],
  columns: ReadonlySet<string>,
  casing: Casing,
): RelationModel[] {
  const snake = (name: string): string =>
    casing === "camel" ? toSnake(name) : name;
  const suffixed = (relation: RelationModel, suffix: string): string =>
    applyCasing(`${snake(relation.name)}_by_${snake(suffix)}`, casing);
  const keyColumns = (relation: RelationModel, all: boolean): string => {
    const { columns: from, references: to, direction } = relation.meta;
    const own = direction === "forward" ? from : to;
    const other = direction === "forward" ? to : from;
    return (all ? own : namingColumns(own, other))
      .map((column) => column.replace(/_?[iI]d$/, ""))
      .join("_");
  };
  const repeated = (names: readonly string[]): Set<string> => {
    const seen = new Set<string>();
    const twice = new Set<string>();
    for (const name of names) (seen.has(name) ? twice : seen).add(name);
    return twice;
  };

  const plain = repeated(list.map((relation) => relation.name));
  const steps = [
    (relation: RelationModel) => suffixed(relation, keyColumns(relation, true)),
    (relation: RelationModel) => suffixed(relation, relation.meta.foreignKey),
  ];
  const names = steps.reduce(
    (current, step) => {
      const clash = repeated(current);
      return list.map((relation, index) => {
        const name = current[index] ?? relation.name;
        return clash.has(name) || columns.has(name) ? step(relation) : name;
      });
    },
    list.map((relation) =>
      plain.has(relation.name) || columns.has(relation.name)
        ? suffixed(relation, keyColumns(relation, false))
        : relation.name,
    ),
  );

  const used = new Set<string>();
  return list.map((relation, index) => {
    let name = names[index] ?? relation.name;
    while (used.has(name) || columns.has(name)) name = `${name}_`;
    used.add(name);
    return { ...relation, name };
  });
}

function realtimeMeta(
  names: readonly string[],
  tables: readonly TableModel[],
): Record<string, RealtimeTableMeta> {
  const out: Record<string, RealtimeTableMeta> = {};
  for (const name of names) {
    const table = tables.find(
      (candidate) =>
        candidate.meta.name === name ||
        `${candidate.meta.schema}.${candidate.meta.name}` === name,
    );
    if (!table) {
      throw new Error(
        `realtime.tables: unknown table "${name}". Check the name and \`schemas\`.`,
      );
    }
    const tenant = table.meta.flags.tenant;
    out[table.key] = tenant ? { tenant } : {};
  }
  return out;
}
