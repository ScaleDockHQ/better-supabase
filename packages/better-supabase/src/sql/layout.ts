import type { ResolvedConfig } from "../config/config.ts";
import type { KitLayout, KitPermdock } from "./kit.ts";

import { resolveJsonSchema } from "../config/config.ts";
import { VERSION } from "../core/version.ts";

/** Where and how `sql add` writes kit files for this config. */
export function kitLayout(
  config: ResolvedConfig,
  testsDir: string = config.sql.testsDir,
  readSets: KitLayout["readSets"] = [],
  permdock?: KitPermdock,
): KitLayout {
  return {
    ...(permdock ? { permdock } : {}),
    dir: config.sql.dir,
    prefix: config.sql.prefix,
    testsDir,
    version: VERSION,
    readSets,
    realtimeTables: config.realtime.tables,
    entitlements: config.entitlements,
    claims: config.claims,
    kits: config.kits,
    vectorSearch: config.vectorSearch,
    grants: Object.entries(config.expose).flatMap(([table, roles]) => [
      { table, role: "anon" as const, privileges: roles.anon },
      {
        table,
        role: "authenticated" as const,
        privileges: roles.authenticated,
      },
    ]),
    jsonSchemas: Object.entries(config.json).flatMap(([key, entry]) => {
      if (!entry.schema) return [];
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
