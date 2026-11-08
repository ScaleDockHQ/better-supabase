import type { FrameworkRegistry } from "../plugins/frameworks.ts";
import type { ExpandedConfig } from "../preset/config.ts";
import type { AuthorizationProvider } from "./authorization.ts";
import type { AnyBlocksConfig, BlockConfig } from "./blocks.ts";
import type { ConfigReferences } from "./references.ts";
import type { Generator } from "./types/codegen.ts";
import type {
  BetterSupabaseConfig,
  FlatConfig,
  HooksFramework,
  ResolvedConfig,
  ResolvedExtensions,
} from "./types/config.ts";
import type {
  ResolvedSeedConfig,
  SeedConfig,
  SqlBlockDefaults,
  SqlConfig,
  VectorSearchConfig,
} from "./types/database.ts";
import type { EntitlementsConfig } from "./types/entitlements.ts";
import type { AppTablesInput } from "./types/groups.ts";

import { DEFAULT_CLAIMS } from "../core/claims.ts";
import { tenantNames } from "../core/entity-naming.ts";
import { frameworkRegistry } from "../plugins/frameworks.ts";
import { expandFlatPreset, expandPreset } from "../preset/config.ts";
import { appTablesOf, withAppTableSubjects } from "./app-tables.ts";
import { providerApiProblem } from "./authorization.ts";
import { withBlockSubjects } from "./block-subjects.ts";
import { tenantNameOf } from "./blocks.ts";
import { CONFIG_DEFAULTS } from "./defaults.ts";
import {
  isFunctionKey,
  resolveExpose,
  resolveExposeFunction,
} from "./expose.ts";
import { flattenConfig } from "./groups.ts";
import { blocksByName, resolveInstances } from "./instances.ts";

function entitlementsOf(
  config: EntitlementsConfig = {},
  provider: boolean,
): ResolvedConfig["entitlements"] {
  const customer = config.customer;
  const dot = customer?.lastIndexOf(".") ?? -1;

  if (customer !== undefined && dot <= 0) {
    throw new TypeError(
      `auth.entitlements.customer must be "table.column", got "${customer}"`,
    );
  }

  return {
    ...(customer === undefined
      ? {}
      : { table: customer.slice(0, dot), column: customer.slice(dot + 1) }),
    key: config.key ?? "id",
    memberships: config.memberships ?? (provider ? "provider" : "tenant"),
    source: config.source ?? "stripe-sync",
    ...(config.claim === undefined ? {} : { claim: config.claim }),
  };
}

function vectorSearchOf(
  config: Readonly<Record<string, VectorSearchConfig>> = {},
): ResolvedConfig["vectorSearch"] {
  return Object.entries(config).map(([table, entry]) =>
    typeof entry === "string"
      ? { table, column: entry, distance: "cosine" }
      : {
          table,
          column: entry.column,
          distance: entry.distance ?? "cosine",
          ...(entry.type === undefined ? {} : { type: entry.type }),
          ...(entry.key === undefined ? {} : { key: entry.key }),
          ...(entry.hybrid === undefined ? {} : { hybrid: entry.hybrid }),
          ...(entry.boost === undefined ? {} : { boost: entry.boost }),
          ...(entry.prefilter === undefined
            ? {}
            : { prefilter: entry.prefilter }),
          ...(entry.predicate === undefined
            ? {}
            : { predicate: entry.predicate }),
          ...(entry.boostMode === undefined
            ? {}
            : { boostMode: entry.boostMode }),
          ...(entry.order === undefined ? {} : { order: entry.order }),
        },
  );
}

/**
 * With `authorization` set, the `access` module's model defaults to `provider`,
 * so `can`, `tenant_ids_with` and every module check answer from the provider's
 * templates instead of the built-in roles.
 */
function isBlockNames(
  blocks: NonNullable<BetterSupabaseConfig["blocks"]>,
): blocks is readonly string[] {
  return Array.isArray(blocks);
}

/**
 * `vector-search` joins the blocks of an app with a `vectorSearch` table, so
 * the search functions need no `blocks` entry of their own.
 */
function withVectorSearch(
  blocks: BetterSupabaseConfig["blocks"],
  vectorSearch: Readonly<Record<string, VectorSearchConfig>> | undefined,
): BetterSupabaseConfig["blocks"] {
  if (vectorSearch === undefined || Object.keys(vectorSearch).length === 0) {
    return blocks;
  }

  if (blocks === undefined) {
    return ["vector-search"];
  }

  if (isBlockNames(blocks)) {
    return blocks.includes("vector-search")
      ? blocks
      : [...blocks, "vector-search"];
  }

  // SAFETY: an empty entry is a valid input for every block key.
  return "vector-search" in blocks
    ? blocks
    : ({ ...blocks, "vector-search": {} } as NonNullable<
        BetterSupabaseConfig["blocks"]
      >);
}

function blocksOf(
  blocks: BetterSupabaseConfig["blocks"],
  sql: SqlConfig = {},
  provider: boolean,
): Pick<ResolvedConfig, "blocks" | "blockNames" | "instances"> {
  const instances = Object.fromEntries(
    Object.entries(resolveInstances(blocks ?? [])).map(([name, instance]) => [
      name,
      { ...instance, config: withSqlDefaults(instance.config, sql) },
    ]),
  );

  const blockNames = [
    ...new Set(Object.values(instances).map((instance) => instance.block)),
  ];

  const resolved =
    Array.isArray(blocks) &&
    sql.schema === undefined &&
    sql.api === undefined &&
    sql.ownTablePolicies === undefined &&
    sql.tenantScope === undefined
      ? {}
      : blocksByName(instances);

  if (
    !provider ||
    !blockNames.includes("permissions") ||
    resolved.permissions?.model !== undefined
  ) {
    return { blocks: resolved, blockNames, instances };
  }

  return {
    blocks: {
      ...resolved,
      permissions: { ...resolved.permissions, model: "provider" },
    },
    blockNames,
    instances,
  };
}

/**
 * `sql.schema` and `sql.api` on every block that leaves its own unset. A
 * block's `api: false` keeps it out of the API schema.
 */
function withSqlDefaults(block: BlockConfig, sql: SqlConfig): BlockConfig {
  const { schema, api, ownTablePolicies, tenantScope } = sql;

  return {
    ...block,
    ...(schema === undefined || block.schema !== undefined ? {} : { schema }),
    ...(api === undefined || block.api !== undefined ? {} : { api }),
    ...(ownTablePolicies === undefined || block.ownTablePolicies !== undefined
      ? {}
      : { ownTablePolicies }),
    ...(tenantScope === undefined || block.tenantScope !== undefined
      ? {}
      : { tenantScope }),
  };
}

function blockDefaultsOf(sql: SqlConfig = {}): {
  readonly blockDefaults?: SqlBlockDefaults;
} {
  const { schema, api, ownTablePolicies, tenantScope } = sql;

  const defaults: SqlBlockDefaults = {
    ...(schema === undefined ? {} : { schema }),
    ...(api === undefined ? {} : { api }),
    ...(ownTablePolicies === undefined ? {} : { ownTablePolicies }),
    ...(tenantScope === undefined ? {} : { tenantScope }),
  };

  return Object.keys(defaults).length === 0 ? {} : { blockDefaults: defaults };
}

export const CONFIG_SCHEMA_URL =
  "https://unpkg.com/better-supabase/schemas/config-v1.json";

/**
 * Types `better-supabase.config.ts` and returns it with its literal types. With
 * `preset`, it expands the preset into `blocks` and its conventions first, and
 * the keys you set win. It checks the references between keys against the
 * config itself: block tables and app tables in `tables` references, the
 * `database.buckets` in `gen.storagePaths`, and the `blocks.permissions.roles`
 * other blocks name.
 */
export function defineConfig<const C extends BetterSupabaseConfig>(
  config: C & NoInfer<ConfigReferences<C>>,
): ExpandedConfig<C> {
  return expandPreset<C>(config);
}

/** A block's option as a string, or `fallback` when it leaves it unset. */
function optionOf(
  blocks: AnyBlocksConfig,
  block: string,
  key: string,
  fallback: string,
): string {
  const value = blocks[block]?.options?.[key];

  return typeof value === "string" ? value : fallback;
}

/**
 * The columns each installed block's repository extension manages. The
 * organization one is on with the `memberships` block, or with
 * `auth.tenant.column` set for an app's own tenancy.
 */
function extensionsOf(
  { blocks, blockNames }: Pick<ResolvedConfig, "blocks" | "blockNames">,
  tenant: FlatConfig["tenant"],
  organizationColumn: string,
): ResolvedExtensions {
  const has = (name: string): boolean => blockNames.includes(name);

  return {
    timestamps: has("updated-at")
      ? {
          createdAt: optionOf(blocks, "updated-at", "createdAt", "created_at"),
          updatedAt: optionOf(blocks, "updated-at", "updatedAt", "updated_at"),
        }
      : undefined,
    softDelete: has("trash")
      ? { column: optionOf(blocks, "trash", "deletedAt", "deleted_at") }
      : undefined,
    tenant:
      has("memberships") || tenant?.column !== undefined
        ? {
            column: tenant?.column ?? organizationColumn,
            ...(tenant?.onMissing === undefined
              ? {}
              : { onMissing: tenant.onMissing }),
            ...(tenant?.header === undefined ? {} : { header: tenant.header }),
          }
        : undefined,
    actor: has("created-by")
      ? {
          createdBy: optionOf(blocks, "created-by", "createdBy", "created_by"),
          updatedBy: optionOf(blocks, "created-by", "updatedBy", "updated_by"),
          impersonatedBy: optionOf(
            blocks,
            "created-by",
            "impersonatedBy",
            "impersonated_by",
          ),
        }
      : undefined,
  };
}

/** The generator contract this release runs. */
const GENERATOR_API = 2;

/**
 * What is wrong with a generator's declaration, or `undefined`. A v1 generator
 * gets the change that broke it: version 2 hands `generate` plain data and
 * wants `version`, so `gen` can cache the files.
 */
export function generatorProblem(generator: Generator): string | undefined {
  const declared: unknown = generator;

  if (typeof declared !== "object" || declared === null) {
    return "a generator is an object: { apiVersion: 2, name, version, generate }";
  }

  const name =
    "name" in declared && typeof declared.name === "string"
      ? declared.name
      : "(unnamed)";

  const api = "apiVersion" in declared ? declared.apiVersion : undefined;

  if (api !== GENERATOR_API) {
    return `generator "${name}" targets generator API ${api === undefined ? "1" : String(api)}; this better-supabase runs ${GENERATOR_API}. API 2 passes \`generate\` plain data (\`config\` is a view, \`imports.runtime\` replaces \`runtimeImport\`, \`importPath\` is \`relativeImport\` in better-supabase/generators) and replaces the \`validators\` flag with \`provides: ["validators"]\`. Build it with defineGenerator, or use a release of the generator for API ${GENERATOR_API}.`;
  }

  if (!("version" in declared) || typeof declared.version !== "string") {
    return `generator "${name}" needs a \`version\` string; it is part of the cache key`;
  }

  return undefined;
}

/**
 * The `gen.hooks` framework: the name the config gives, or the binding the
 * `integrations` select, or `false`. A name nothing registers is an error.
 */
function hooksOf(
  config: FlatConfig,
  frameworks: FrameworkRegistry,
): HooksFramework | false {
  const named =
    typeof config.hooks === "object" ? config.hooks.framework : config.hooks;

  if (named === undefined) {
    return frameworks.forIntegrations(config.adapters ?? [])?.name ?? false;
  }

  if (named !== false && frameworks.get(named) === undefined) {
    throw new TypeError(
      `gen.hooks names framework "${named}", which nothing registers; the registered frameworks are ${frameworks.names.join(", ")}. Register one with \`frameworks: [defineFramework({ ... })]\`.`,
    );
  }

  return named;
}

function generatorsOf(
  generators: readonly Generator[] | undefined,
): readonly Generator[] {
  for (const generator of generators ?? []) {
    const problem = generatorProblem(generator);

    if (problem !== undefined) {
      throw new TypeError(problem);
    }
  }

  return generators ?? [];
}

function authorizationOf(
  provider: AuthorizationProvider,
): AuthorizationProvider {
  const problem = providerApiProblem(provider);

  if (problem !== undefined) {
    throw new TypeError(problem);
  }

  return provider;
}

/**
 * The grouped config plus the app tables a Create design and `migrate
 * schema-first` hand in. Tables are SQL files, so the public config has no key
 * for them (ADR 0102).
 */
export type ResolveInput = BetterSupabaseConfig & {
  readonly appTables?: AppTablesInput;
};

/** Applies defaults. Paths stay relative to `root`. */
export function resolveConfig(
  input: ResolveInput,
  root: string,
): ResolvedConfig {
  const config = expandFlatPreset(flattenConfig(input));
  const frameworks = frameworkRegistry(config.frameworks);
  const output = config.file ?? CONFIG_DEFAULTS.output;
  const tenantName = tenantNameOf(config.blocks);
  const appTables = appTablesOf(config.appTables, tenantName);

  const blocks = blocksOf(
    withVectorSearch(config.blocks, config.vectorSearch),
    config.sql,
    config.authorization !== undefined,
  );

  return {
    root,
    source: config.source ?? {},
    schemas: config.schemas ?? CONFIG_DEFAULTS.schemas,
    casing: config.casing ?? CONFIG_DEFAULTS.casing,
    tables: config.tables ?? {},
    output,
    databaseTypesOutput: output.replace(/[^/]+$/, "database.types.ts"),
    postgrestVersion:
      config.postgrestVersion ?? CONFIG_DEFAULTS.postgrestVersion,
    records: config.records ?? true,
    hooks: hooksOf(config, frameworks),
    frameworks: frameworks.bindings,
    ...(typeof config.hooks === "object" && config.hooks.select !== undefined
      ? { hooksSelect: config.hooks.select }
      : {}),
    json: config.json ?? {},
    codecs: {
      timestamptz:
        config.codecs?.timestamptz ?? CONFIG_DEFAULTS.codecs.timestamptz,
      int8: config.codecs?.int8 ?? CONFIG_DEFAULTS.codecs.int8,
      numeric: config.codecs?.numeric ?? CONFIG_DEFAULTS.codecs.numeric,
    },
    relations: {
      nullableUnderRls: config.relations?.nullableUnderRls ?? false,
    },
    sensitive: config.sensitive ?? [],
    storagePaths: config.storagePaths ?? {},
    functions: config.functions ?? {},
    expose: Object.fromEntries(
      Object.entries(config.expose ?? {})
        .filter(([key]) => !isFunctionKey(key))
        .map(([table, entry]) => [table, resolveExpose(table, entry)]),
    ),
    exposeFunctions: Object.fromEntries(
      Object.entries(config.expose ?? {})
        .filter(([key]) => isFunctionKey(key))
        .map(([fn, entry]) => [fn, resolveExposeFunction(fn, entry)]),
    ),
    readSets: config.readSets ?? [],
    generators: generatorsOf(config.generators),
    extensions: extensionsOf(
      blocks,
      config.tenant,
      tenantNames(tenantName).rename("organization_id"),
    ),
    claims: { ...DEFAULT_CLAIMS, ...config.claims },
    buckets: config.buckets ?? {},
    topics: config.topics ?? {},
    realtime: {
      tables: config.realtime?.tables ?? [],
      global: config.realtime?.global ?? [],
      users: config.realtime?.users ?? {},
      triggers: config.realtime?.triggers ?? [],
      ...(config.realtime?.policies === undefined
        ? {}
        : { policies: config.realtime.policies }),
    },
    entitlements: entitlementsOf(
      config.entitlements,
      config.authorization !== undefined,
    ),
    ...(config.authorization === undefined
      ? {}
      : { authorization: authorizationOf(config.authorization) }),
    vectorSearch: vectorSearchOf(config.vectorSearch),
    subjects: withBlockSubjects(
      withAppTableSubjects(
        config.recordTypes ?? {},
        appTables,
        config.sql?.scope,
        tenantName,
      ),
      blocks.blockNames,
      blocks.blocks,
      config.sql?.tenantColumn,
    ),
    sql: {
      ...(config.sql?.workflow === undefined
        ? {}
        : { workflow: config.sql.workflow }),
      dir: config.sql?.dir ?? CONFIG_DEFAULTS.sql.dir,
      prefix: config.sql?.prefix ?? CONFIG_DEFAULTS.sql.prefix,
      testsDir: config.sql?.testsDir ?? CONFIG_DEFAULTS.sql.testsDir,
      ...(config.sql?.scope === undefined ? {} : { scope: config.sql.scope }),
      ...(config.sql?.tenantColumn === undefined
        ? {}
        : { tenantColumn: config.sql.tenantColumn }),
      ...blockDefaultsOf(config.sql),
    },
    ...(config.preset === undefined ? {} : { preset: config.preset }),
    ...blocks,
    appTables,
    seed: {
      entry: config.seed?.entry ?? CONFIG_DEFAULTS.seed.entry,
      file: config.seed?.file ?? CONFIG_DEFAULTS.seed.file,
      perTenant: config.seed?.perTenant ?? CONFIG_DEFAULTS.seed.perTenant,
      ...resolveSeedModes(config.seed),
    },
    specs: {
      entry: config.specs?.entry ?? CONFIG_DEFAULTS.specs.entry,
      outputs: config.specs?.outputs ?? [
        { format: "openapi", file: CONFIG_DEFAULTS.specs.file },
      ],
      failOn: config.specs?.failOn ?? CONFIG_DEFAULTS.specs.failOn,
      ...(config.specs?.manifest === undefined
        ? {}
        : { manifest: config.specs.manifest }),
    },
    doctor: {
      ignore: config.doctor?.ignore ?? [],
      only: config.doctor?.only ?? [],
      strict: config.doctor?.strict ?? false,
      format: config.doctor?.format ?? CONFIG_DEFAULTS.doctor.format,
      sources: config.doctor?.sources ?? CONFIG_DEFAULTS.doctor.sources,
      policyHelperLimit:
        config.doctor?.policyHelperLimit ??
        CONFIG_DEFAULTS.doctor.policyHelperLimit,
      sealTriggers: config.doctor?.sealTriggers ?? [],
      ...(config.doctor?.file === undefined
        ? {}
        : { file: config.doctor.file }),
      ...(config.doctor?.claimsLimit === undefined
        ? {}
        : { claimsLimit: config.doctor.claimsLimit }),
      ...(config.doctor?.migrationSafety === undefined
        ? {}
        : { migrationSafety: config.doctor.migrationSafety }),
      ...(config.doctor?.baseline === undefined
        ? {}
        : { baseline: config.doctor.baseline }),
    },
    gen: {
      ...config.gen,
      watchInterval:
        config.gen?.watchInterval ?? CONFIG_DEFAULTS.gen.watchInterval,
    },
    env: {
      file: config.env?.file ?? CONFIG_DEFAULTS.env.file,
      ...(config.env?.prefix === undefined
        ? {}
        : { prefix: config.env.prefix }),
    },
    adapters: config.adapters ?? [],
    skills: config.skills ?? {},
    keys: config.keys ?? {},
  };
}

function resolveSeedModes(
  seed: SeedConfig | undefined,
): Pick<ResolvedSeedConfig, "defaults" | "sample"> {
  const raw = seed?.defaults;
  const defaults = typeof raw === "object" ? raw : {};
  const locale = defaults.locale ?? CONFIG_DEFAULTS.seed.defaults.locale;

  return {
    defaults: {
      enabled: raw !== false,
      onCreate: defaults.onCreate ?? CONFIG_DEFAULTS.seed.defaults.onCreate,
      locale,
      variants: defaults.variants ?? {},
    },
    sample: {
      size: seed?.sample?.size ?? CONFIG_DEFAULTS.seed.sample.size,
      seed: seed?.sample?.seed ?? CONFIG_DEFAULTS.seed.sample.seed,
      locale: seed?.sample?.locale ?? locale,
      file: seed?.sample?.file ?? CONFIG_DEFAULTS.seed.sample.file,
    },
  };
}
