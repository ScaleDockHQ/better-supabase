import type { GeneratorModel, ResolvedConfig } from "../../config/index.ts";
import type {
  Casing,
  ClaimsMeta,
  ColumnMeta,
  FunctionMeta,
  FunctionSignature,
  RealtimeTableMeta,
  RelationMeta,
  SchemaMeta,
  TableMeta,
} from "../../index.ts";
import type { Catalog, CatalogTable, Snapshot } from "../introspect/types.ts";

import { DEFAULT_CLAIMS, tenantClaimPaths } from "../../config/index.ts";
import { toCamel } from "../../index.ts";
import { resolveProviderSql } from "../../sql/index.ts";
import { CliError } from "../errors.ts";
import { toCatalog } from "../introspect/catalog.ts";
import {
  type GeneratorMetadata,
  restrictSchemas,
  tsTypeOf,
} from "../introspect/typegen.ts";
import { commentMeta } from "./comment.ts";
import { buildFunctions } from "./model-functions.ts";
import { buildRelations, namingColumns } from "./model-relations.ts";
import {
  type ColumnModel,
  type DraftTable,
  type EnumModel,
  type FunctionModel,
  type JsonImport,
  type ModelContext,
  type RelationModel,
  type TableModel,
  CODEC_TYPE,
  applyCasing,
  codecFor,
  enumType,
} from "./model-types.ts";
import {
  arrayOf,
  configFor,
  identifier,
  isJsonUdt,
  parseCheckNotNull,
  parseCheckUnion,
  pascal,
} from "./shared.ts";

export type { ColumnModel, FunctionModel } from "./model-types.ts";

const SOFT_DELETE_UDTS = new Set(["timestamptz", "timestamp"]);

/** The overloads of each function name, in model order. */
export function functionGroups(
  functions: readonly FunctionModel[],
): Map<string, FunctionModel[]> {
  const groups = new Map<string, FunctionModel[]>();

  for (const fn of functions) {
    const group = groups.get(fn.key);

    if (group) {
      group.push(fn);
    } else {
      groups.set(fn.key, [fn]);
    }
  }

  return groups;
}

function signatureOf(fn: FunctionModel): FunctionSignature {
  const { name: _name, schema: _schema, ...signature } = fn.meta;

  return {
    ...signature,
    args: signature.args.map((arg, index) =>
      fn.args[index]?.optional ? { ...arg, optional: true } : arg,
    ),
  };
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

  if (schemas.length === 1 || table.schema === "public") {
    return base;
  }

  return applyCasing(`${table.schema}_${table.name}`, casing);
}

const TEXT_UDTS = new Set(["text", "varchar", "bpchar"]);

/** `config.storagePaths` resolved to bucket ids, with a check that every key is used. */
function storagePathsOf(config: ResolvedConfig) {
  const bucketId = (name: string): string => {
    const bucket = config.buckets[name];

    if (!bucket) {
      return name;
    }

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

      if (key === undefined) {
        return;
      }

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

function prepareCatalog(
  snapshot: Snapshot,
  config: ResolvedConfig,
): ModelContext {
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

  const jsonTypeFor = (
    schema: string,
    table: string,
    column: string,
  ): string | undefined => {
    const key = [`${schema}.${table}.${column}`, `${table}.${column}`].find(
      (candidate) => candidate in config.json,
    );

    const override = key === undefined ? undefined : config.json[key];

    if (key === undefined || !override) {
      return undefined;
    }

    unusedJson.delete(key);

    if ("type" in override) {
      return override.type;
    }

    const [from, name] = override.import.split("#");

    if (!from || !name) {
      throw new TypeError(
        `json["${key}"].import must look like "./path.ts#TypeName"`,
      );
    }

    jsonImports.set(name, { name, from });

    return name;
  };

  const optionsOf = (table: CatalogTable) =>
    configFor(config.tables, table.schema, table.name);

  const included = catalog.tables.filter(
    (table) =>
      config.schemas.includes(table.schema) && !optionsOf(table)?.exclude,
  );

  const keyOf = new Map<string, string>();
  const ownerOf = new Map<string, string>();

  for (const table of included) {
    const id = `${table.schema}.${table.name}`;
    const key = tableKey(table, config.casing, config.schemas);
    const other = ownerOf.get(key);

    if (other !== undefined) {
      throw new TypeError(
        `${other} and ${id} both generate the model key "${key}". Exclude one with \`tables["${id}"].exclude\`, or rename one of the tables.`,
      );
    }

    ownerOf.set(key, id);
    keyOf.set(id, key);
  }

  return {
    config,
    catalog,
    introspection,
    enumsByName,
    jsonImports,
    unusedJson,
    included,
    keyOf,
    warnings: [],
    tsType,
    jsonTypeFor,
    optionsOf,
  };
}

function draftTables(ctx: ModelContext): DraftTable[] {
  const { config, included, enumsByName, tsType, jsonTypeFor, optionsOf } = ctx;
  const storagePaths = storagePathsOf(config);

  const tables = included.map((table) => {
    const casing = optionsOf(table)?.casing ?? config.casing;
    const checks = new Map<string, string[]>();
    const checkedNotNull = new Set<string>();

    for (const check of table.checks) {
      const union = parseCheckUnion(check.definition);

      if (union) {
        checks.set(union.column, union.values);
      }

      for (const column of parseCheckNotNull(check.definition)) {
        checkedNotNull.add(column);
      }
    }

    const beforeInsert = table.triggers.some(
      (trigger) =>
        trigger.timing === "before" &&
        trigger.level === "row" &&
        trigger.events.includes("insert"),
    );

    const insertOptional = new Set(optionsOf(table)?.insertOptional);

    for (const name of insertOptional) {
      if (!table.columns.some((column) => column.name === name)) {
        throw new TypeError(
          `tables.${table.name}.insertOptional: "${name}" is not a column of ${table.schema}.${table.name}`,
        );
      }
    }

    const columns = table.columns.map((column): ColumnModel => {
      const enumValues = column.isEnum
        ? enumsByName.get(`${column.typeSchema}.${column.udt}`)
        : undefined;

      const values = enumValues ?? checks.get(column.name);
      const json = isJsonUdt(column.udt);

      const override = json
        ? jsonTypeFor(table.schema, table.name, column.name)
        : undefined;

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

      // A view's computed columns are neither insertable nor updatable;
      // Postgres reports both through is_updatable.
      const insertable =
        !readonly &&
        table.insertable &&
        (table.kind !== "view" || column.updatable);

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

    const byApp = new Map<string, string>();

    for (const column of columns) {
      const other = byApp.get(column.app);

      if (other !== undefined) {
        throw new TypeError(
          `${table.schema}.${table.name}: columns "${other}" and "${column.db}" both become "${column.app}". Rename one, or set \`tables["${table.schema}.${table.name}"].casing: "snake"\`.`,
        );
      }

      byApp.set(column.app, column.db);
    }

    const byDb = new Map(columns.map((column) => [column.db, column]));

    return { table, casing, columns, byDb };
  });

  storagePaths.assertUsed();

  return tables;
}

/** Config entries that match no table or column. */
function configWarnings(ctx: ModelContext): string[] {
  const { config, catalog, unusedJson } = ctx;
  const schemasOf = new Map<string, string[]>();

  for (const table of catalog.tables) {
    if (!config.schemas.includes(table.schema)) {
      continue;
    }

    schemasOf.set(table.name, [
      ...(schemasOf.get(table.name) ?? []),
      table.schema,
    ]);
  }

  const known = (key: string): boolean => {
    const dot = key.indexOf(".");

    if (dot === -1) {
      return schemasOf.has(key);
    }

    return (
      schemasOf.get(key.slice(dot + 1))?.includes(key.slice(0, dot)) ?? false
    );
  };

  const warnings = [
    ...Object.keys(config.tables)
      .filter((name) => !known(name))
      .map(
        (name) =>
          `tables["${name}"]: no table by that name in ${config.schemas.join(", ")}, so the entry does nothing.`,
      ),
    ...Object.keys(config.tables).flatMap((name) => {
      const shared = (schemasOf.get(name) ?? [])
        .filter((schema) => !(`${schema}.${name}` in config.tables))
        .map((schema) => `${schema}.${name}`);

      return shared.length > 1
        ? [
            `tables["${name}"]: ${shared.join(" and ")} share the name, so the entry applies to each. Key it \`schema.table\` to pick one.`,
          ]
        : [];
    }),
    ...[...unusedJson].map(
      (key) =>
        `json["${key}"]: no json or jsonb column by that name, so the type is not used. Keys are \`table.column\` or \`schema.table.column\` with database names.`,
    ),
  ];

  return warnings;
}

function toTableModels(
  ctx: ModelContext,
  tables: readonly DraftTable[],
  relations: ReadonlyMap<string, RelationModel[]>,
): TableModel[] {
  const { config, keyOf, optionsOf } = ctx;
  const flagsConfig = config.plugins;
  const subjectDeletedAt = new Map<string, { db: string; source: string }>();

  for (const [type, subject] of Object.entries(config.subjects)) {
    if (subject.deletedAt !== undefined) {
      const table = subject.table.includes(".")
        ? subject.table
        : `public.${subject.table}`;

      subjectDeletedAt.set(table, {
        db: subject.deletedAt,
        source: `subjects.${type}.deletedAt`,
      });
    }
  }

  const tableModels: TableModel[] = tables.map(
    ({ table, casing, columns, byDb }) => {
      const id = `${table.schema}.${table.name}`;
      const renames = optionsOf(table)?.relations ?? {};
      const columnNames = new Set(columns.map((column) => column.app));

      const list = dedupeRelations(
        relations.get(id) ?? [],
        columnNames,
        casing,
      ).map((relation) => ({
        ...relation,
        name: renames[relation.name] ?? relation.name,
      }));

      const has = (db: string): string | undefined => byDb.get(db)?.app;

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

      const subjectColumn = subjectDeletedAt.get(id);

      const softDelete =
        subjectColumn !== undefined && byDb.has(subjectColumn.db)
          ? subjectColumn
          : flagsConfig.softDelete
            ? {
                db: flagsConfig.softDelete.column,
                source: "plugins.softDelete.column",
              }
            : undefined;

      const softDeleteColumn = softDelete && byDb.get(softDelete.db);

      if (softDelete && softDeleteColumn) {
        const udt = softDeleteColumn.snapshot.udt;

        if (softDeleteColumn.snapshot.isArray || !SOFT_DELETE_UDTS.has(udt)) {
          throw new TypeError(
            `${softDelete.source}: ${id}.${softDelete.db} is ${udt}, but softDelete() writes a timestamp. Use timestamptz or timestamp.`,
          );
        }

        flags.softDelete = softDeleteColumn.app;
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

        if (column) {
          flags.tenant = column;
        }
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

        if (column.readonly) {
          meta.generated = true;
        }

        if (column.snapshot.identity) {
          meta.identity = column.snapshot.identity;
        }

        if (!column.readonly && !column.insertable) {
          meta.insertable = false;
        }

        if (!column.readonly && !column.updatable) {
          meta.updatable = false;
        }

        if (column.snapshot.isArray) {
          meta.array = true;
        }

        if (column.json) {
          meta.json = true;
        }

        if (column.values) {
          meta.enum = column.values;
        }

        if (column.codec) {
          meta.codec = column.codec;
        }

        if (column.storage) {
          meta.storage = column.storage;
        }

        if (
          config.sensitive.includes(`${table.name}.${column.db}`) ||
          config.sensitive.includes(
            `${table.schema}.${table.name}.${column.db}`,
          )
        ) {
          meta.sensitive = true;
        }

        Object.assign(meta, commentMeta(column.snapshot.comment));
        columnMeta[column.app] = meta;
      }

      const app = (db: string): string => byDb.get(db)?.app ?? db;
      const uniqueKeys: Record<string, readonly string[]> = {};

      for (const unique of table.uniques) {
        uniqueKeys[unique.name] = unique.columns.map(app);
      }

      const relationMeta: Record<string, RelationMeta> = {};

      for (const relation of list) {
        relationMeta[relation.name] = relation.meta;
      }

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
          flags,
          ...commentMeta(table.comment),
        },
      };
    },
  );

  return tableModels;
}

function buildEnums(ctx: ModelContext): EnumModel[] {
  const { config, catalog } = ctx;

  const includedEnums = catalog.enums.filter((entry) =>
    config.schemas.includes(entry.schema),
  );

  const enumNameCount = new Map<string, number>();

  for (const entry of includedEnums) {
    enumNameCount.set(entry.name, (enumNameCount.get(entry.name) ?? 0) + 1);
  }

  const enums: EnumModel[] = includedEnums.map((entry) => {
    const key =
      entry.schema !== "public" && (enumNameCount.get(entry.name) ?? 0) > 1
        ? `${entry.schema}_${entry.name}`
        : entry.name;

    return {
      schema: entry.schema,
      name: entry.name,
      key,
      constant: identifier(`${toCamel(key)}Values`),
      typeName: identifier(pascal(key)),
      values: entry.values,
    };
  });

  return enums;
}

function assembleMeta(
  config: ResolvedConfig,
  tableModels: readonly TableModel[],
  enums: readonly EnumModel[],
  functions: readonly FunctionModel[],
): SchemaMeta {
  const tablesMeta: Record<string, TableMeta> = {};

  for (const table of tableModels) {
    tablesMeta[table.key] = table.meta;
  }

  const enumsMeta: Record<string, readonly string[]> = {};

  for (const entry of enums) {
    enumsMeta[entry.key] = entry.values;
  }

  const functionsMeta: Record<string, FunctionMeta> = {};

  for (const [key, group] of functionGroups(functions)) {
    const [first] = group;

    if (!first) {
      continue;
    }

    functionsMeta[key] =
      group.length === 1
        ? first.meta
        : { ...first.meta, overloads: group.map(signatureOf) };
  }

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
                ...(bucket.policy
                  ? {
                      policy:
                        typeof bucket.policy === "string"
                          ? bucket.policy
                          : resolveProviderSql(
                              `buckets.${name}`,
                              bucket.policy,
                              config.authorization?.functions,
                            ),
                    }
                  : {}),
                ...(bucket.policy === "tenant" && tenantClaim
                  ? { tenant: { claim: tenantClaim } }
                  : {}),
                ...(bucket.fileSizeLimit
                  ? { fileSizeLimit: bucket.fileSizeLimit }
                  : {}),
                ...(bucket.allowedMimeTypes
                  ? { allowedMimeTypes: bucket.allowedMimeTypes }
                  : {}),
                ...(bucket.versioning ? { versioning: true } : {}),
                ...(bucket.lifecycle ? { lifecycle: bucket.lifecycle } : {}),
              },
            ]),
          ),
        }
      : {}),
    ...(Object.keys(config.topics).length > 0 ? { topics: config.topics } : {}),
    ...(config.realtime.tables.length > 0
      ? {
          realtime: realtimeMeta(
            config.realtime.tables,
            config.realtime.users,
            tableModels,
          ),
        }
      : {}),
    ...(Object.keys(claimOverrides).length > 0
      ? { claims: claimOverrides }
      : {}),
  };

  return meta;
}

/** Builds the codegen model from a snapshot and config. */
export function buildModel(snapshot: Snapshot, config: ResolvedConfig): Model {
  const ctx = prepareCatalog(snapshot, config);
  const tables = draftTables(ctx);
  ctx.warnings.push(...configWarnings(ctx));
  const relations = buildRelations(ctx, tables);
  const tableModels = toTableModels(ctx, tables, relations);
  const enums = buildEnums(ctx);
  const functions = buildFunctions(ctx, tableModels);

  return {
    tables: tableModels,
    enums,
    functions,
    jsonImports: [...ctx.jsonImports.values()],
    meta: assembleMeta(config, tableModels, enums, functions),
    config,
    catalog: ctx.catalog,
    introspection: ctx.introspection,
    warnings: ctx.warnings,
  };
}

function deepFreeze<T>(value: T): T {
  if (typeof value === "object" && value !== null && !Object.isFrozen(value)) {
    Object.freeze(value);

    for (const entry of Object.values(value)) {
      deepFreeze(entry);
    }
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
  const suffixed = (relation: RelationModel, suffix: string): string =>
    applyCasing(`${relation.base}_by_${suffix}`, casing);

  const keyColumns = (relation: RelationModel, all: boolean): string =>
    (all
      ? relation.fkColumns
      : namingColumns(relation.fkColumns, relation.refColumns)
    )
      .map((column) => column.replace(/_?[iI]d$/, ""))
      .join("_");

  const repeated = (names: readonly string[]): Set<string> => {
    const seen = new Set<string>();
    const twice = new Set<string>();

    for (const name of names) {
      (seen.has(name) ? twice : seen).add(name);
    }

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

    while (used.has(name) || columns.has(name)) {
      name = `${name}_`;
    }

    used.add(name);

    return { ...relation, name };
  });
}

function realtimeMeta(
  names: readonly string[],
  users: Readonly<Record<string, string>>,
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
      throw new CliError(
        "config_invalid",
        `realtime.tables: unknown table "${name}". Check the name and \`schemas\`.`,
      );
    }

    const owner = users[name];

    if (owner !== undefined) {
      const user = Object.entries(table.meta.columns).find(
        ([, column]) => column.db === owner,
      )?.[0];

      if (user === undefined) {
        throw new CliError(
          "config_invalid",
          `realtime.users: "${name}" has no column "${owner}".`,
        );
      }

      out[table.key] = { user };
      continue;
    }

    const tenant = table.meta.flags.tenant;
    out[table.key] = tenant ? { tenant } : {};
  }

  return out;
}
