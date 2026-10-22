import type { ResolvedConfig } from "../config/index.ts";
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
    ...(config.authorization?.delegation?.scopes
      ? { delegationScopes: config.authorization.delegation.scopes }
      : {}),
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
    subjects: config.subjects,
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
      if (!entry.schema) {
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
