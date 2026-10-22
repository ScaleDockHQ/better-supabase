import type { ExpandedConfig } from "../preset/config.ts";
import type { AuthorizationProvider } from "./authorization.ts";
import type { AnyBlocksConfig } from "./blocks.ts";
import type { ConfigReferences } from "./references.ts";
import type { Generator } from "./types/codegen.ts";
import type {
  BetterSupabaseConfig,
  FlatConfig,
  ResolvedConfig,
  ResolvedExtensions,
} from "./types/config.ts";
import type { SqlConfig, VectorSearchConfig } from "./types/database.ts";
import type { EntitlementsConfig } from "./types/entitlements.ts";

import { DEFAULT_CLAIMS } from "../core/claims.ts";
import { tenantNames } from "../core/entity-naming.ts";
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
function blocksOf(
  blocks: BetterSupabaseConfig["blocks"],
  sql: SqlConfig = {},
  provider: boolean,
): Pick<ResolvedConfig, "blocks" | "blockNames"> {
  const config = blocks ?? [];
  const blockNames = isBlockList(config) ? config : Object.keys(config);

  const resolved = withSqlDefaults(
    isBlockList(config) ? {} : config,
    blockNames,
    sql,
  );

  if (
    !provider ||
    !blockNames.includes("permissions") ||
    resolved.permissions?.model !== undefined
  ) {
    return { blocks: resolved, blockNames };
  }

  return {
    blocks: {
      ...resolved,
      permissions: { ...resolved.permissions, model: "provider" },
    },
    blockNames,
  };
}

/**
 * `sql.schema` and `sql.api` on every block that leaves its own unset. A
 * block's `api: false` keeps it out of the API schema.
 */
function withSqlDefaults(
  modules: AnyBlocksConfig,
  names: readonly string[],
  sql: SqlConfig,
): AnyBlocksConfig {
  if (sql.schema === undefined && sql.api === undefined) {
    return modules;
  }

  const { schema, api } = sql;

  return Object.fromEntries(
    names.map((name) => {
      const module = modules[name] ?? {};

      return [
        name,
        {
          ...module,
          ...(schema === undefined || module.schema !== undefined
            ? {}
            : { schema }),
          ...(api === undefined || module.api !== undefined ? {} : { api }),
        },
      ];
    }),
  );
}

function isBlockList(
  config: NonNullable<FlatConfig["blocks"]>,
): config is readonly string[] {
  return Array.isArray(config);
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
 * `auth.organization.column` set for an app's own tenancy.
 */
function extensionsOf(
  { blocks, blockNames }: Pick<ResolvedConfig, "blocks" | "blockNames">,
  organization: FlatConfig["organization"],
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
      has("memberships") || organization?.column !== undefined
        ? {
            column: organization?.column ?? organizationColumn,
            ...(organization?.onMissing === undefined
              ? {}
              : { onMissing: organization.onMissing }),
            ...(organization?.header === undefined
              ? {}
              : { header: organization.header }),
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

function generatorsOf(
  generators: readonly Generator[] | undefined,
): readonly Generator[] {
  for (const generator of generators ?? []) {
    const version: unknown = generator.apiVersion;

    if (version !== undefined && version !== 1) {
      throw new TypeError(
        `generator "${generator.name}" targets generator API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the generator for API 1.`,
      );
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

/** Applies defaults. Paths stay relative to `root`. */
export function resolveConfig(
  input: BetterSupabaseConfig,
  root: string,
): ResolvedConfig {
  const config = expandFlatPreset(flattenConfig(input));
  const output = config.output ?? CONFIG_DEFAULTS.output;
  // oxlint-disable-next-line typescript/no-deprecated -- the deprecated key still resolves, and maps onto specs
  const legacyOpenApi = config.openapi;
  const tenantName = tenantNameOf(config.blocks);
  const appTables = appTablesOf(config.appTables, tenantName);

  const blocks = blocksOf(
    config.blocks,
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
    generateFeatures: config.generateFeatures ?? true,
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
      config.organization,
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
        config.subjects ?? {},
        appTables,
        config.sql?.scope,
        tenantName,
      ),
      blocks.blockNames,
      blocks.blocks,
    ),
    sql: {
      ...(config.sql?.workflow === undefined
        ? {}
        : { workflow: config.sql.workflow }),
      dir: config.sql?.dir ?? CONFIG_DEFAULTS.sql.dir,
      prefix: config.sql?.prefix ?? CONFIG_DEFAULTS.sql.prefix,
      testsDir: config.sql?.testsDir ?? CONFIG_DEFAULTS.sql.testsDir,
      ...(config.sql?.scope === undefined ? {} : { scope: config.sql.scope }),
    },
    ...(config.preset === undefined ? {} : { preset: config.preset }),
    ...blocks,
    appTables,
    seed: {
      entry: config.seed?.entry ?? CONFIG_DEFAULTS.seed.entry,
      output: config.seed?.output ?? CONFIG_DEFAULTS.seed.output,
      perTenant: config.seed?.perTenant ?? CONFIG_DEFAULTS.seed.perTenant,
    },
    openapi: {
      entry: legacyOpenApi?.entry ?? CONFIG_DEFAULTS.openapi.entry,
      output: legacyOpenApi?.output ?? CONFIG_DEFAULTS.openapi.output,
    },
    specs: {
      entry:
        config.specs?.entry ??
        legacyOpenApi?.entry ??
        CONFIG_DEFAULTS.openapi.entry,
      outputs: config.specs?.outputs ?? [
        {
          format: "openapi",
          output: legacyOpenApi?.output ?? CONFIG_DEFAULTS.openapi.output,
        },
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
      ...(config.doctor?.output === undefined
        ? {}
        : { output: config.doctor.output }),
      ...(config.doctor?.claimsLimit === undefined
        ? {}
        : { claimsLimit: config.doctor.claimsLimit }),
      ...(config.doctor?.migrationSafety === undefined
        ? {}
        : { migrationSafety: config.doctor.migrationSafety }),
    },
    gen: {
      ...config.gen,
      watchInterval:
        config.gen?.watchInterval ?? CONFIG_DEFAULTS.gen.watchInterval,
    },
    env: {
      output: config.env?.output ?? CONFIG_DEFAULTS.env.output,
      ...(config.env?.prefix === undefined
        ? {}
        : { prefix: config.env.prefix }),
    },
    scaffold: config.scaffold ?? {},
    integrations: config.integrations ?? [],
    skills: config.skills ?? {},
    keys: config.keys ?? {},
  };
}
