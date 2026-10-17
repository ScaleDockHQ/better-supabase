import type { ResolvedConfig } from "../config/index.ts";
import type {
  ModuleAccessProvider,
  ModuleEntitlementsProvider,
  ModuleLayout,
} from "./module-types.ts";

import { resolveJsonSchema } from "../config/json.ts";
import { VERSION } from "../core/version.ts";

/** Where and how `sql add` writes module files for this config. */
export function moduleLayout(
  config: ResolvedConfig,
  testsDir: string = config.sql.testsDir,
  readSets: ModuleLayout["readSets"] = [],
  entitlementsProvider?: ModuleEntitlementsProvider,
  accessProvider?: ModuleAccessProvider,
  permissionCatalog?: readonly string[],
): ModuleLayout {
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
    version: VERSION,
    readSets,
    realtimeTables: config.realtime.tables,
    realtimeGlobal: config.realtime.global,
    realtimeUsers: config.realtime.users,
    entitlements: config.entitlements,
    claims: config.claims,
    modules: config.blocks,
    ...(config.sql.scope === undefined ? {} : { scope: config.sql.scope }),
    ...(config.sql.naming === undefined ? {} : { naming: config.sql.naming }),
    subjects: config.subjects,
    vectorSearch: config.vectorSearch,
    grants: Object.entries(config.expose).flatMap(([table, roles]) => [
      { table, role: "anon" as const, privileges: roles.anon },
      {
        table,
        role: "authenticated" as const,
        privileges: roles.authenticated,
      },
      {
        table,
        role: "service_role" as const,
        privileges: roles.serviceRole,
      },
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
    ...(config.plugins.tenant
      ? { tenantColumn: config.plugins.tenant.column }
      : {}),
  };
}
