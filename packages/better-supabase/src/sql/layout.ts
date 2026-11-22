import type {
  AuthorizationActionKeys,
  AuthorizationApproval,
  AuthorizationOperation,
  ResolvedConfig,
} from "../config/index.ts";
import type {
  BlockSqlAccessProvider,
  BlockSqlEntitlementsProvider,
  BlockSqlLayout,
} from "./module-types.ts";

import { resolveJsonSchema } from "../config/json.ts";

/** Where and how `add` writes module files for this config. */
export function moduleLayout(
  config: ResolvedConfig,
  testsDir: string = config.sql.testsDir,
  readSets: BlockSqlLayout["readSets"] = [],
  entitlementsProvider?: BlockSqlEntitlementsProvider,
  accessProvider?: BlockSqlAccessProvider,
  permissionCatalog?: readonly string[],
): BlockSqlLayout {
  return {
    ...(entitlementsProvider ? { entitlementsProvider } : {}),
    ...(accessProvider ? { accessProvider } : {}),
    ...(permissionCatalog ? { permissionCatalog } : {}),
    ...providerApprovalsOf(config.authorization?.operations),
    ...(config.authorization?.actionKeys
      ? { providerActionKeys: config.authorization.actionKeys }
      : {}),
    ...(config.authorization?.versions
      ? {
          authzVersionsProvider: {
            name: config.authorization.name,
            function: config.authorization.versions.function,
          },
        }
      : {}),
    ...(config.authorization?.delegation?.scopes
      ? { delegationScopes: config.authorization.delegation.scopes }
      : {}),
    ...(config.authorization?.delegation?.interactiveOnly
      ? {
          delegationInteractiveOnly:
            config.authorization.delegation.interactiveOnly,
        }
      : {}),
    seedDefaults: config.seed.defaults,
    dir: config.sql.dir,
    prefix: config.sql.prefix,
    testsDir,
    readSets,
    realtimeTables: config.realtime.tables,
    realtimeGlobal: config.realtime.global,
    realtimeUsers: config.realtime.users,
    entitlements: config.entitlements,
    claims: config.claims,
    modules: config.blocks,
    instances: config.instances,
    ...(config.sql.scope === undefined ? {} : { scope: config.sql.scope }),
    ...(config.sql.tenantColumn === undefined
      ? {}
      : { blockTenantColumn: config.sql.tenantColumn }),
    ...(config.sql.brand === undefined ? {} : { blockBrand: config.sql.brand }),
    subjects: withProviderKeys(
      config.subjects,
      config.authorization?.actionKeys,
    ),
    appTables: config.appTables,
    vectorSearch: config.vectorSearch,
    grants: Object.entries(config.expose).flatMap(([table, roles]) => [
      { table, role: "anon" as const, privileges: roles.anon },
      {
        table,
        role: "authenticated" as const,
        privileges: roles.authenticated,
      },
      { table, role: "service_role" as const, privileges: roles.serviceRole },
    ]),
    functionGrants: Object.entries(config.exposeFunctions).map(
      ([fn, roles]) => ({ function: fn, roles }),
    ),
    jsonSchemas: Object.entries(config.json).flatMap(([key, entry]) => {
      if (!entry.schema || typeof entry.schema === "string") {
        return [];
      }

      const dot = key.lastIndexOf(".");

      return [
        {
          table: key.slice(0, dot),
          column: key.slice(dot + 1),
          schema: resolveJsonSchema(entry.schema),
        },
      ];
    }),
    ...(config.extensions.tenant
      ? { tenantColumn: config.extensions.tenant.column }
      : {}),
  };
}

/**
 * The record types with the permission keys the provider gives their actions
 * (`authorization.actionKeys.recordTypes`). An entry the config sets wins.
 */
export function withProviderKeys(
  subjects: ResolvedConfig["subjects"],
  actionKeys: AuthorizationActionKeys | undefined,
): ResolvedConfig["subjects"] {
  const byType = actionKeys?.recordTypes;

  if (byType === undefined) {
    return subjects;
  }

  return Object.fromEntries(
    Object.entries(subjects).map(([type, entry]) => {
      const keys = byType[type];

      return [
        type,
        keys === undefined
          ? entry
          : { ...entry, permissions: { ...keys, ...entry.permissions } },
      ];
    }),
  );
}

/** The operations that carry an approval floor, by operation name. */
function providerApprovalsOf(
  operations: Readonly<Record<string, AuthorizationOperation>> | undefined,
): { providerApprovals?: Record<string, AuthorizationApproval> } {
  const entries = Object.entries(operations ?? {}).flatMap(([name, op]) =>
    op.approval === undefined ? [] : [[name, op.approval] as const],
  );

  return entries.length === 0
    ? {}
    : { providerApprovals: Object.fromEntries(entries) };
}
